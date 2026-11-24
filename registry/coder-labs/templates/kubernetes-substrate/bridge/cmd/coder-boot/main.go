// coder-boot is the entry point of the Coder workspace actor. An actor is
// restored from the template's golden snapshot, so it cannot get a Coder
// agent token from its environment. coder-boot asks the broker for the
// token of the actor it runs in, and runs `coder agent` with it. The egress
// gateway adds an actor JWT to each broker request, and the broker returns
// only the token of the workspace that the JWT names. When the token
// changes (a new workspace build), coder-boot restarts the agent.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"io"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

type grant struct {
	AgentURL string `json:"agent_url"`
	Token    string `json:"token"`
}

func main() {
	broker := flag.String("broker", "http://broker.substrate.internal/token", "broker URL")
	listen := flag.String("listen", ":8080", "address of the wakeup probe")
	idle := flag.Duration("idle-poll", 200*time.Millisecond, "poll interval while no agent runs")
	busy := flag.Duration("busy-poll", time.Second, "poll interval while the agent runs")
	uid := flag.Int("uid", 1000, "user and group ID for the agent when coder-boot runs as root")
	home := flag.String("home", "/home/coder", "home directory of the agent user")
	flag.Parse()

	// The microVM root file system shows every image file as owned by
	// root. Give the home back to the agent user before the wakeup probe
	// passes, so the golden snapshot already has it.
	if os.Getuid() == 0 {
		t := time.Now()
		if err := chownTree(*home, *uid); err != nil {
			log.Printf("chown %s: %v", *home, err)
		}
		log.Printf("home owned by %d in %s", *uid, time.Since(t).Round(time.Millisecond))
	}

	var (
		mu      sync.Mutex
		running bool
	)
	http.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	http.HandleFunc("/status", func(w http.ResponseWriter, _ *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		_ = json.NewEncoder(w).Encode(map[string]bool{"agent_running": running})
	})
	go func() { log.Fatal(http.ListenAndServe(*listen, nil)) }()

	client := &http.Client{Timeout: 5 * time.Second}
	var (
		current string
		cmd     *exec.Cmd
		exited  chan struct{}
	)
	stop := func(grace time.Duration) {
		if cmd == nil {
			return
		}
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		select {
		case <-exited:
		case <-time.After(grace):
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
			<-exited
		}
		cmd = nil
	}
	for {
		interval := *idle
		if cmd != nil {
			interval = *busy
			select {
			case <-exited:
				log.Printf("agent exited, restarting")
				cmd, current = nil, ""
				interval = *idle
			default:
			}
		}
		g, err := fetch(client, *broker)
		switch {
		case errors.Is(err, errNoToken):
			// The workspace is stopped or not built yet.
			if cmd != nil {
				log.Printf("token withdrawn, stopping agent")
				stop(5 * time.Second)
				current = ""
			}
		case err != nil:
			// Keep the running agent on transient broker errors.
		case g.Token != current:
			// A new build revoked the old token, so the old agent has
			// nothing to finish.
			stop(200 * time.Millisecond)
			c := exec.Command("/usr/local/bin/coder", "agent")
			c.Env = append(os.Environ(),
				"CODER_AGENT_URL="+g.AgentURL,
				"CODER_AGENT_TOKEN="+g.Token,
				"CODER_AGENT_AUTH=token",
			)
			c.Env = append(c.Env, linkLocalEnv...)
			c.Stdout, c.Stderr = os.Stdout, os.Stderr
			// Substrate starts the container as root whatever the image's
			// USER is. Run the agent, and so every shell and tool, as the
			// image's coder user like the other templates.
			c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
			if os.Getuid() == 0 {
				c.SysProcAttr.Credential = &syscall.Credential{Uid: uint32(*uid), Gid: uint32(*uid), Groups: []uint32{uint32(*uid)}}
				c.Dir = *home
			}
			if err := c.Start(); err != nil {
				log.Printf("start agent: %v", err)
				break
			}
			log.Printf("agent started")
			cmd, current = c, g.Token
			exited = make(chan struct{})
			go func(c *exec.Cmd, done chan struct{}) { _ = c.Wait(); close(done) }(c, exited)
		}
		mu.Lock()
		running = cmd != nil
		mu.Unlock()
		wait(interval)
	}
}

// wait sleeps for d. It returns early when the wall clock jumps ahead,
// which is what a resume from a snapshot looks like from inside: a new
// build is starting and has a new token.
func wait(d time.Duration) {
	start := time.Now().Round(0)
	deadline := time.Now().Add(d)
	for time.Now().Before(deadline) {
		time.Sleep(100 * time.Millisecond)
		if time.Now().Round(0).Sub(start) > d+time.Second {
			return
		}
	}
}

// chownTree gives dir and everything under it to uid. Root here has no
// CAP_DAC_OVERRIDE, so once a directory belongs to uid, root can no longer
// list or enter it. It lists the tree first and changes children before
// their parents.
func chownTree(dir string, uid int) error {
	var paths []string
	err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		if st, ok := info.Sys().(*syscall.Stat_t); ok && int(st.Uid) == uid && int(st.Gid) == uid {
			return nil
		}
		paths = append(paths, p)
		return nil
	})
	if err != nil {
		return err
	}
	for i := len(paths) - 1; i >= 0; i-- {
		if err := os.Lchown(paths[i], uid, uid); err != nil {
			return err
		}
	}
	return nil
}

var errNoToken = errors.New("no token for this actor")

// linkLocalEnv makes Tailscale in the agent use the actor's address. An
// actor's only interface has a link-local address (169.254.17.2), and
// Tailscale counts link-local addresses as "no network" except on AWS
// Lambda and Azure App Service (net/interfaces.isUsableV4). Without a
// usable address the agent never runs netcheck, never picks a home DERP,
// and no client can connect to it. These are the variables that
// hostinfo.inAWSLambda checks. Tailscale uses the result only for that
// check and for host info.
var linkLocalEnv = []string{
	"AWS_LAMBDA_FUNCTION_NAME=coder-substrate-actor",
	"AWS_LAMBDA_FUNCTION_VERSION=1",
	"AWS_LAMBDA_INITIALIZATION_TYPE=on-demand",
	"AWS_LAMBDA_RUNTIME_API=127.0.0.1:9",
}

func fetch(client *http.Client, url string) (grant, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return grant{}, err
	}
	// The egress gateway replaces this placeholder with an actor JWT.
	req.Header.Set("Authorization", "placeholder")
	res, err := client.Do(req)
	if err != nil {
		return grant{}, err
	}
	defer res.Body.Close()
	if res.StatusCode == http.StatusNotFound {
		return grant{}, errNoToken
	}
	if res.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(io.LimitReader(res.Body, 512))
		return grant{}, errors.New(res.Status + ": " + string(b))
	}
	var g grant
	if err := json.NewDecoder(io.LimitReader(res.Body, 64<<10)).Decode(&g); err != nil {
		return grant{}, err
	}
	if g.Token == "" || g.AgentURL == "" {
		return grant{}, errors.New("broker returned an empty grant")
	}
	return g, nil
}
