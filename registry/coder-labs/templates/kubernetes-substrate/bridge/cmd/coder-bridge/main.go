// coder-bridge connects Coder workspaces to Agent Substrate actors. It runs
// in the Substrate cluster and does three jobs:
//
//   - Controller: it reads the workspace ConfigMaps and agent Secrets that
//     the Coder template writes to the Coder cluster, and creates, resumes,
//     suspends, and deletes one actor per workspace with kubectl-ate.
//   - Broker: an actor asks it for its Coder agent token. The egress gateway
//     adds an actor JWT to the request. The broker checks the JWT against
//     the Substrate issuer and returns only the token of that actor.
//   - Coder front: Substrate egress does not allow WebSockets on http and
//     https rules, and the Coder agent needs them. Actors reach Coder with a
//     tls_passthrough rule instead. This listener ends that TLS and copies
//     the bytes to the Coder server.
package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"os"
	"os/exec"
	"sort"
	"strings"
	"sync"
	"time"
)

type config struct {
	coderUpstream string
	agentURL      string
	coderListen   string
	brokerListen  string
	tlsCert       string
	tlsKey        string
	idpURL        string
	idpCA         string
	audience      string
	atespace      string
	actorTemplate string
	kubeAPI       string
	kubeToken     string
	kubeCA        string
	kubeNamespace string
	ateEndpoint   string
	ateToken      string
	poll          time.Duration
}

func main() {
	var c config
	flag.StringVar(&c.coderUpstream, "coder-upstream", "", "host:port of the Coder server, plain HTTP")
	flag.StringVar(&c.agentURL, "agent-url", "https://coder.substrate.internal", "Coder URL that actors use")
	flag.StringVar(&c.coderListen, "coder-listen", ":8443", "TLS listener for the Coder front")
	flag.StringVar(&c.brokerListen, "broker-listen", ":8080", "HTTP listener for the broker")
	flag.StringVar(&c.tlsCert, "tls-cert", "/tls/tls.crt", "")
	flag.StringVar(&c.tlsKey, "tls-key", "/tls/tls.key", "")
	flag.StringVar(&c.idpURL, "idp-url", "https://idp.ate-system.svc", "Substrate actor JWT issuer")
	flag.StringVar(&c.idpCA, "idp-ca", "/trust/servicedns.pem", "CA bundle of the issuer's TLS certificate")
	flag.StringVar(&c.audience, "audience", "coder-bridge", "actor JWT audience")
	flag.StringVar(&c.atespace, "atespace", "coder", "")
	flag.StringVar(&c.actorTemplate, "actor-template", "coder-workspace", "")
	flag.StringVar(&c.kubeAPI, "coder-kube-api", "", "API server URL of the Coder cluster")
	flag.StringVar(&c.kubeToken, "coder-kube-token", "/coder-kube/token", "")
	flag.StringVar(&c.kubeCA, "coder-kube-ca", "/coder-kube/ca.crt", "")
	flag.StringVar(&c.kubeNamespace, "coder-kube-namespace", "coder-substrate", "")
	flag.StringVar(&c.ateEndpoint, "ate-endpoint", "api.ate-system.svc:443", "")
	flag.StringVar(&c.ateToken, "ate-token", "/var/run/secrets/ate/token", "")
	flag.DurationVar(&c.poll, "poll", 250*time.Millisecond, "how often to read the Coder cluster")
	flag.Parse()

	b := &bridge{cfg: c, grants: map[string]string{}}
	go b.serveCoderFront()
	go b.serveBroker()
	b.reconcileLoop()
}

type bridge struct {
	cfg config

	mu     sync.RWMutex
	grants map[string]string // actor name -> agent token

	keysMu sync.Mutex
	keys   map[string]*ecdsa.PublicKey
	issuer string
}

// Coder front.

func (b *bridge) serveCoderFront() {
	cert, err := tls.LoadX509KeyPair(b.cfg.tlsCert, b.cfg.tlsKey)
	if err != nil {
		log.Fatalf("load TLS key pair: %v", err)
	}
	ln, err := tls.Listen("tcp", b.cfg.coderListen, &tls.Config{Certificates: []tls.Certificate{cert}, MinVersion: tls.VersionTLS12})
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("accept: %v", err)
			continue
		}
		go func() {
			defer conn.Close()
			up, err := net.DialTimeout("tcp", b.cfg.coderUpstream, 5*time.Second)
			if err != nil {
				log.Printf("dial Coder: %v", err)
				return
			}
			defer up.Close()
			done := make(chan struct{}, 2)
			go func() { _, _ = io.Copy(up, conn); done <- struct{}{} }()
			go func() { _, _ = io.Copy(conn, up); done <- struct{}{} }()
			<-done
		}()
	}
}

// Broker.

func (b *bridge) serveBroker() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /token", func(w http.ResponseWriter, r *http.Request) {
		raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok {
			http.Error(w, "missing actor JWT", http.StatusUnauthorized)
			return
		}
		atespace, name, err := b.verify(raw)
		if err != nil {
			log.Printf("reject token request: %v", err)
			http.Error(w, "invalid actor JWT", http.StatusUnauthorized)
			return
		}
		if atespace != b.cfg.atespace {
			http.Error(w, "wrong atespace", http.StatusForbidden)
			return
		}
		b.mu.RLock()
		token, ok := b.grants[name]
		b.mu.RUnlock()
		if !ok {
			http.Error(w, "no running workspace for this actor", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		_ = json.NewEncoder(w).Encode(map[string]string{"agent_url": b.cfg.agentURL, "token": token})
	})
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	log.Fatal(http.ListenAndServe(b.cfg.brokerListen, mux))
}

type jwtHeader struct {
	Alg string `json:"alg"`
	Kid string `json:"kid"`
}

type jwtClaims struct {
	Iss string          `json:"iss"`
	Sub string          `json:"sub"`
	Aud json.RawMessage `json:"aud"`
	Exp int64           `json:"exp"`
	Nbf int64           `json:"nbf"`
}

// verify checks an ES256 actor JWT and returns the actor's atespace and
// name from its subject, "actor/<atespace>/<name>".
func (b *bridge) verify(raw string) (string, string, error) {
	parts := strings.Split(raw, ".")
	if len(parts) != 3 {
		return "", "", errors.New("not a JWT")
	}
	var h jwtHeader
	if err := decodeSegment(parts[0], &h); err != nil {
		return "", "", err
	}
	if h.Alg != "ES256" {
		return "", "", fmt.Errorf("unsupported alg %q", h.Alg)
	}
	key, issuer, err := b.key(h.Kid)
	if err != nil {
		return "", "", err
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(sig) != 64 {
		return "", "", errors.New("bad signature encoding")
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if !ecdsa.Verify(key, digest[:], new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])) {
		return "", "", errors.New("bad signature")
	}
	var c jwtClaims
	if err := decodeSegment(parts[1], &c); err != nil {
		return "", "", err
	}
	now := time.Now().Unix()
	if c.Iss != issuer {
		return "", "", fmt.Errorf("issuer %q, want %q", c.Iss, issuer)
	}
	if c.Exp == 0 || now > c.Exp+30 || (c.Nbf != 0 && now < c.Nbf-30) {
		return "", "", errors.New("token expired or not yet valid")
	}
	if !hasAudience(c.Aud, b.cfg.audience) {
		return "", "", errors.New("wrong audience")
	}
	f := strings.Split(c.Sub, "/")
	if len(f) != 3 || f[0] != "actor" {
		return "", "", fmt.Errorf("unexpected subject %q", c.Sub)
	}
	return f[1], f[2], nil
}

func hasAudience(raw json.RawMessage, want string) bool {
	var one string
	if json.Unmarshal(raw, &one) == nil {
		return one == want
	}
	var many []string
	if json.Unmarshal(raw, &many) == nil {
		for _, a := range many {
			if a == want {
				return true
			}
		}
	}
	return false
}

func decodeSegment(s string, v any) error {
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

// key returns the issuer's public key for kid, refreshing the JWK set once
// when kid is unknown, so key rotation works.
func (b *bridge) key(kid string) (*ecdsa.PublicKey, string, error) {
	b.keysMu.Lock()
	defer b.keysMu.Unlock()
	if k, ok := b.keys[kid]; ok {
		return k, b.issuer, nil
	}
	if err := b.loadKeys(); err != nil {
		return nil, "", err
	}
	if k, ok := b.keys[kid]; ok {
		return k, b.issuer, nil
	}
	return nil, "", fmt.Errorf("unknown key %q", kid)
}

func (b *bridge) loadKeys() error {
	ca, err := os.ReadFile(b.cfg.idpCA)
	if err != nil {
		return fmt.Errorf("read issuer CA: %w", err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(ca) {
		return errors.New("issuer CA has no certificates")
	}
	client := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool}}}
	var disc struct {
		Issuer  string `json:"issuer"`
		JWKSURI string `json:"jwks_uri"`
	}
	if err := getJSON(client, b.cfg.idpURL+"/.well-known/openid-configuration", &disc); err != nil {
		return err
	}
	var set struct {
		Keys []struct {
			Kty, Crv, Kid, X, Y string
		} `json:"keys"`
	}
	if disc.JWKSURI == "" {
		return errors.New("discovery document has no jwks_uri")
	}
	if err := getJSON(client, disc.JWKSURI, &set); err != nil {
		return err
	}
	keys := map[string]*ecdsa.PublicKey{}
	for _, k := range set.Keys {
		if k.Kty != "EC" || k.Crv != "P-256" {
			continue
		}
		x, err1 := base64.RawURLEncoding.DecodeString(k.X)
		y, err2 := base64.RawURLEncoding.DecodeString(k.Y)
		if err1 != nil || err2 != nil {
			continue
		}
		keys[k.Kid] = &ecdsa.PublicKey{Curve: elliptic.P256(), X: new(big.Int).SetBytes(x), Y: new(big.Int).SetBytes(y)}
	}
	b.keys, b.issuer = keys, disc.Issuer
	return nil
}

func getJSON(client *http.Client, url string, v any) error {
	res, err := client.Get(url)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("GET %s: %s", url, res.Status)
	}
	return json.NewDecoder(io.LimitReader(res.Body, 1<<20)).Decode(v)
}

// Controller.

type workspace struct {
	actor    string
	policy   string // egress policy YAML
	template string
	token    string // empty when the workspace is stopped
}

type actorState struct {
	exists bool
	policy string
	state  string
	// After a failure, the next attempt waits until retryAt.
	retryAt  time.Time
	failures int
}

func (b *bridge) reconcileLoop() {
	kube := b.coderKube()
	known := map[string]*actorState{}
	if names, err := b.listActors(); err == nil {
		for _, n := range names {
			known[n] = &actorState{exists: true}
		}
	} else {
		log.Printf("list actors: %v", err)
	}
	for {
		want, err := b.readWorkspaces(kube)
		if err != nil {
			log.Printf("read workspaces: %v", err)
			time.Sleep(time.Second)
			continue
		}
		grants := map[string]string{}
		for name, ws := range want {
			if ws.token != "" {
				grants[name] = ws.token
			}
		}
		// Publish grants before resuming, so a resumed actor gets its
		// token on its first poll.
		b.mu.Lock()
		b.grants = grants
		b.mu.Unlock()

		var wg sync.WaitGroup
		for name, ws := range want {
			st := known[name]
			if st == nil {
				st = &actorState{}
				known[name] = st
			}
			wg.Add(1)
			go func(ws workspace, st *actorState) {
				defer wg.Done()
				b.reconcile(ws, st)
			}(ws, st)
		}
		for name, st := range known {
			if _, ok := want[name]; ok || !st.exists {
				continue
			}
			wg.Add(1)
			go func(name string, st *actorState) {
				defer wg.Done()
				t := time.Now()
				if err := b.ate("delete", "actor", name, "-a", b.cfg.atespace); err != nil && !strings.Contains(err.Error(), "NotFound") {
					log.Printf("delete %s: %v", name, err)
					return
				}
				log.Printf("deleted %s in %s", name, time.Since(t).Round(time.Millisecond))
				st.exists = false
			}(name, st)
		}
		wg.Wait()
		for name, st := range known {
			if _, ok := want[name]; !ok && !st.exists {
				delete(known, name)
			}
		}
		time.Sleep(b.cfg.poll)
	}
}

func (b *bridge) reconcile(ws workspace, st *actorState) {
	if time.Now().Before(st.retryAt) {
		return
	}
	if err := b.reconcileOnce(ws, st); err != nil {
		// Back off up to 2 s, so a full worker pool is retried soon after
		// a worker frees up, without a call every poll. Log the first
		// failure of a run and every 30th.
		if st.failures%30 == 0 {
			log.Printf("%s: %v (retrying)", ws.actor, err)
		}
		st.failures++
		st.retryAt = time.Now().Add(min(time.Duration(st.failures)*250*time.Millisecond, 2*time.Second))
		return
	}
	if st.failures > 0 {
		log.Printf("%s: recovered after %d failed attempts", ws.actor, st.failures)
	}
	st.failures = 0
}

func (b *bridge) reconcileOnce(ws workspace, st *actorState) error {
	if !st.exists {
		t := time.Now()
		err := b.ate("create", "actor", ws.actor, "-a", b.cfg.atespace, "--template", ws.template)
		if err != nil && !strings.Contains(err.Error(), "AlreadyExists") {
			return fmt.Errorf("create: %w", err)
		}
		log.Printf("created %s in %s", ws.actor, time.Since(t).Round(time.Millisecond))
		st.exists = true
		st.state = "suspended"
	}
	if st.policy != ws.policy {
		t := time.Now()
		var err error
		update := st.policy != ""
		if !update {
			err = b.ateStdin(ws.policy, "create", "egress-policy", ws.actor, "-a", b.cfg.atespace, "-f", "-")
			update = err != nil && strings.Contains(err.Error(), "AlreadyExists")
		}
		if update {
			// An update must name the uid and version it replaces.
			var pre string
			if pre, err = b.policyPreconditions(ws.actor); err == nil {
				policy := strings.Replace(ws.policy, "  name: default\n", "  name: default\n"+pre, 1)
				err = b.ateStdin(policy, "update", "egress-policy", ws.actor, "-a", b.cfg.atespace, "-f", "-")
			}
		}
		if err != nil {
			return fmt.Errorf("egress policy: %w", err)
		}
		log.Printf("egress policy %s set in %s", ws.actor, time.Since(t).Round(time.Millisecond))
		st.policy = ws.policy
	}
	switch {
	case ws.token != "" && st.state != "running":
		t := time.Now()
		if err := b.ate("resume", "actor", ws.actor, "-a", b.cfg.atespace); err != nil {
			return fmt.Errorf("resume: %w", err)
		}
		log.Printf("resumed %s in %s", ws.actor, time.Since(t).Round(time.Millisecond))
		st.state = "running"
	case ws.token == "" && st.state != "suspended":
		t := time.Now()
		if err := b.ate("suspend", "actor", ws.actor, "-a", b.cfg.atespace); err != nil && !strings.Contains(err.Error(), "already") {
			return fmt.Errorf("suspend: %w", err)
		}
		log.Printf("suspended %s in %s", ws.actor, time.Since(t).Round(time.Millisecond))
		st.state = "suspended"
	}
	return nil
}

func (b *bridge) ate(args ...string) error { return b.ateStdin("", args...) }

// policyPreconditions returns the uid and version lines of the actor's
// current egress policy, indented for its metadata block.
func (b *bridge) policyPreconditions(actor string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	out, err := exec.CommandContext(ctx, "kubectl-ate", "--endpoint", b.cfg.ateEndpoint, "--token-file", b.cfg.ateToken,
		"get", "egress-policy", actor, "-a", b.cfg.atespace, "-o", "yaml").Output()
	if err != nil {
		return "", fmt.Errorf("get egress policy: %w", err)
	}
	var pre string
	for _, line := range strings.Split(string(out), "\n") {
		if strings.HasPrefix(line, "  uid: ") || strings.HasPrefix(line, "  version: ") {
			pre += line + "\n"
		}
	}
	if strings.Count(pre, "\n") != 2 {
		return "", errors.New("egress policy has no uid and version")
	}
	return pre, nil
}

func (b *bridge) ateStdin(stdin string, args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	full := append([]string{"--endpoint", b.cfg.ateEndpoint, "--token-file", b.cfg.ateToken}, args...)
	cmd := exec.CommandContext(ctx, "kubectl-ate", full...)
	if stdin != "" {
		cmd.Stdin = strings.NewReader(stdin)
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%v: %s", err, bytes.TrimSpace(out))
	}
	return nil
}

func (b *bridge) listActors() ([]string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	out, err := exec.CommandContext(ctx, "kubectl-ate", "--endpoint", b.cfg.ateEndpoint, "--token-file", b.cfg.ateToken,
		"get", "actors", "-a", b.cfg.atespace).CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("%v: %s", err, bytes.TrimSpace(out))
	}
	var names []string
	for _, line := range strings.Split(string(out), "\n") {
		if f := strings.Fields(line); len(f) > 1 && strings.HasPrefix(f[1], "ws-") {
			names = append(names, f[1])
		}
	}
	return names, nil
}

type kubeClient struct {
	http  *http.Client
	base  string
	token string
}

func (b *bridge) coderKube() *kubeClient {
	ca, err := os.ReadFile(b.cfg.kubeCA)
	if err != nil {
		log.Fatalf("read Coder cluster CA: %v", err)
	}
	pool := x509.NewCertPool()
	pool.AppendCertsFromPEM(ca)
	tok, err := os.ReadFile(b.cfg.kubeToken)
	if err != nil {
		log.Fatalf("read Coder cluster token: %v", err)
	}
	return &kubeClient{
		http:  &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool}}},
		base:  strings.TrimRight(b.cfg.kubeAPI, "/") + "/api/v1/namespaces/" + b.cfg.kubeNamespace,
		token: strings.TrimSpace(string(tok)),
	}
}

type kubeList struct {
	Items []struct {
		Metadata struct {
			Name   string            `json:"name"`
			Labels map[string]string `json:"labels"`
		} `json:"metadata"`
		Data map[string]string `json:"data"`
	} `json:"items"`
}

func (k *kubeClient) list(kind string) (kubeList, error) {
	var l kubeList
	req, _ := http.NewRequest(http.MethodGet, k.base+"/"+kind+"?labelSelector=app.kubernetes.io%2Fpart-of%3Dcoder-substrate", nil)
	req.Header.Set("Authorization", "Bearer "+k.token)
	res, err := k.http.Do(req)
	if err != nil {
		return l, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(res.Body, 512))
		return l, fmt.Errorf("list %s: %s: %s", kind, res.Status, b)
	}
	return l, json.NewDecoder(res.Body).Decode(&l)
}

// readWorkspaces returns the wanted actors. A workspace ConfigMap lives as
// long as the workspace; an agent Secret exists only while it is started.
func (b *bridge) readWorkspaces(k *kubeClient) (map[string]workspace, error) {
	cms, err := k.list("configmaps")
	if err != nil {
		return nil, err
	}
	secs, err := k.list("secrets")
	if err != nil {
		return nil, err
	}
	tokens := map[string]string{}
	for _, s := range secs.Items {
		a := s.Metadata.Labels["coder.com/actor"]
		t, err := base64.StdEncoding.DecodeString(s.Data["token"])
		if a != "" && err == nil && len(t) > 0 {
			tokens[a] = string(t)
		}
	}
	want := map[string]workspace{}
	for _, cm := range cms.Items {
		a := cm.Metadata.Labels["coder.com/actor"]
		if !strings.HasPrefix(a, "ws-") {
			continue
		}
		var hosts []string
		_ = json.Unmarshal([]byte(cm.Data["hosts"]), &hosts)
		ports := []int{443}
		if p := cm.Data["ports"]; p != "" {
			ports = nil
			_ = json.Unmarshal([]byte(p), &ports)
		}
		tpl := cm.Data["template"]
		if tpl == "" {
			tpl = b.cfg.actorTemplate
		}
		want[a] = workspace{actor: a, template: tpl, token: tokens[a], policy: b.policyYAML(hosts, ports)}
	}
	return want, nil
}

// policyYAML builds the egress policy: Coder through the TLS front, the
// broker with an actor JWT, and the profile's hosts. Port 443 is TLS passed
// through without interception, and port 80 is plain HTTP. Other ports are
// ignored.
func (b *bridge) policyYAML(hosts []string, ports []int) string {
	sort.Strings(hosts)
	var sb strings.Builder
	fmt.Fprintf(&sb, "metadata:\n  atespace: %s\n  name: default\nrules:\n", b.cfg.atespace)
	sb.WriteString("- tlsPassthrough:\n    hostnames: [\"coder.substrate.internal\"]\n    ports: {numbers: [443]}\n")
	fmt.Fprintf(&sb, "- http:\n    hostnames: [\"broker.substrate.internal\"]\n    ports: {numbers: [80]}\n    effects:\n      replaceHeaders:\n      - header: Authorization\n        prefix: \"Bearer \"\n        actorJwt:\n          audiences: [%q]\n          expirationSeconds: 900\n", b.cfg.audience)
	if len(hosts) == 0 {
		return sb.String()
	}
	q := make([]string, len(hosts))
	for i, h := range hosts {
		q[i] = fmt.Sprintf("%q", h)
	}
	list := strings.Join(q, ", ")
	for _, p := range ports {
		switch p {
		case 443:
			fmt.Fprintf(&sb, "- tlsPassthrough:\n    hostnames: [%s]\n    ports: {numbers: [443]}\n", list)
		case 80:
			fmt.Fprintf(&sb, "- http:\n    hostnames: [%s]\n    ports: {numbers: [80]}\n", list)
		}
	}
	return sb.String()
}
