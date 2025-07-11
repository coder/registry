// Package gorules defines custom lint rules for ruleguard.
//
// golangci-lint runs these rules via go-critic, which includes support
// for ruleguard. All Go files in this directory define lint rules
// in the Ruleguard DSL; see:
//
// - https://go-ruleguard.github.io/by-example/
// - https://pkg.go.dev/github.com/quasilyte/go-ruleguard/dsl
//
// You run one of the following commands to execute your go rules only:
//
//	golangci-lint run
//	golangci-lint run --disable-all --enable=gocritic
//
// Note: don't forget to run `golangci-lint cache clean`!
package gorules

import (
	"github.com/quasilyte/go-ruleguard/dsl"
)

// Use xerrors everywhere! It provides additional stacktrace info!
//
//nolint:unused,deadcode,varnamelen
func xerrors(m dsl.Matcher) {
	m.Import("errors")
	m.Import("fmt")
	m.Import("golang.org/x/xerrors")

	m.Match("fmt.Errorf($arg)").
		Suggest("xerrors.New($arg)").
		Report("Use xerrors to provide additional stacktrace information!")

	m.Match("fmt.Errorf($arg1, $*args)").
		Suggest("xerrors.Errorf($arg1, $args)").
		Report("Use xerrors to provide additional stacktrace information!")

	m.Match("errors.$_($msg)").
		Where(m["msg"].Type.Is("string")).
		Suggest("xerrors.New($msg)").
		Report("Use xerrors to provide additional stacktrace information!")
}

// databaseImport enforces not importing any database types into /codersdk.
//
//nolint:unused,deadcode,varnamelen
func databaseImport(m dsl.Matcher) {
	m.Import("github.com/coder/coder/v2/coderd/database")
	m.Match("database.$_").
		Report("Do not import any database types into codersdk").
		Where(m.File().PkgPath.Matches("github.com/coder/coder/v2/codersdk"))
}

// doNotCallTFailNowInsideGoroutine enforces not calling t.FailNow or
// functions that may themselves call t.FailNow in goroutines outside
// the main test goroutine. See testing.go:834 for why.
//
//nolint:unused,deadcode,varnamelen
func doNotCallTFailNowInsideGoroutine(m dsl.Matcher) {
	m.Import("testing")
	m.Match(`
	go func($*_){
		$*_
		$require.$_($*_)
		$*_
	}($*_)`).
		At(m["require"]).
		Where(m["require"].Text == "require").
		Report("Do not call functions that may call t.FailNow in a goroutine, as this can cause data races (see testing.go:834)")

	// require.Eventually runs the function in a goroutine.
	m.Match(`
	require.Eventually(t, func() bool {
		$*_
		$require.$_($*_)
		$*_
	}, $*_)`).
		At(m["require"]).
		Where(m["require"].Text == "require").
		Report("Do not call functions that may call t.FailNow in a goroutine, as this can cause data races (see testing.go:834)")

	m.Match(`
	go func($*_){
		$*_
		$t.$fail($*_)
		$*_
	}($*_)`).
		At(m["fail"]).
		Where(m["t"].Type.Implements("testing.TB") && m["fail"].Text.Matches("^(FailNow|Fatal|Fatalf)$")).
		Report("Do not call functions that may call t.FailNow in a goroutine, as this can cause data races (see testing.go:834)")
}

// useStandardTimeoutsAndDelaysInTests ensures all tests use common
// constants for timeouts and delays in usual scenarios, this allows us
// to tweak them based on platform (important to avoid CI flakes).
//
//nolint:unused,deadcode,varnamelen
func useStandardTimeoutsAndDelaysInTests(m dsl.Matcher) {
	m.Import("github.com/stretchr/testify/require")
	m.Import("github.com/stretchr/testify/assert")
	m.Import("github.com/coder/coder/v2/testutil")

	m.Match(`context.WithTimeout($ctx, $duration)`).
		Where(m.File().Imports("testing") && !m.File().PkgPath.Matches("testutil$") && !m["duration"].Text.Matches("^testutil\\.")).
		At(m["duration"]).
		Report("Do not use magic numbers in test timeouts and delays. Use the standard testutil.Wait* or testutil.Interval* constants instead.")

	m.Match(`
		$testify.$Eventually($t, func() bool {
			$*_
		}, $timeout, $interval, $*_)
	`).
		Where((m["testify"].Text == "require" || m["testify"].Text == "assert") &&
			(m["Eventually"].Text == "Eventually" || m["Eventually"].Text == "Eventuallyf") &&
			!m["timeout"].Text.Matches("^testutil\\.")).
		At(m["timeout"]).
		Report("Do not use magic numbers in test timeouts and delays. Use the standard testutil.Wait* or testutil.Interval* constants instead.")

	m.Match(`
		$testify.$Eventually($t, func() bool {
			$*_
		}, $timeout, $interval, $*_)
	`).
		Where((m["testify"].Text == "require" || m["testify"].Text == "assert") &&
			(m["Eventually"].Text == "Eventually" || m["Eventually"].Text == "Eventuallyf") &&
			!m["interval"].Text.Matches("^testutil\\.")).
		At(m["interval"]).
		Report("Do not use magic numbers in test timeouts and delays. Use the standard testutil.Wait* or testutil.Interval* constants instead.")
}

// ProperRBACReturn ensures we always write to the response writer after a
// call to Authorize. If we just do a return, the client will get a status code
// 200, which is incorrect.
func ProperRBACReturn(m dsl.Matcher) {
	m.Match(`
	if !$_.Authorize($*_) {
		return
	}
	`).Report("Must write to 'ResponseWriter' before returning'")
}

// slogFieldNameSnakeCase is a lint rule that ensures naming consistency
// of logged field names.
func slogFieldNameSnakeCase(m dsl.Matcher) {
	m.Import("cdr.dev/slog")
	m.Match(
		`slog.F($name, $value)`,
	).
		Where(m["name"].Const && !m["name"].Text.Matches(`^"[a-z]+(_[a-z]+)*"$`)).
		Report("Field name $name must be snake_case.")
}

// slogUUIDFieldNameHasIDSuffix ensures that "uuid.UUID" field has ID prefix
// in the field name.
func slogUUIDFieldNameHasIDSuffix(m dsl.Matcher) {
	m.Import("cdr.dev/slog")
	m.Import("github.com/google/uuid")
	m.Match(
		`slog.F($name, $value)`,
	).
		Where(m["value"].Type.Is("uuid.UUID") && !m["name"].Text.Matches(`_id"$`)).
		Report(`uuid.UUID field $name must have "_id" suffix.`)
}

// slogMessageFormat ensures that the log message starts with lowercase, and does not
// end with special character.
func slogMessageFormat(m dsl.Matcher) {
	m.Import("cdr.dev/slog")
	m.Match(
		`logger.Error($ctx, $message, $*args)`,
		`logger.Warn($ctx, $message, $*args)`,
		`logger.Info($ctx, $message, $*args)`,
		`logger.Debug($ctx, $message, $*args)`,

		`$foo.logger.Error($ctx, $message, $*args)`,
		`$foo.logger.Warn($ctx, $message, $*args)`,
		`$foo.logger.Info($ctx, $message, $*args)`,
		`$foo.logger.Debug($ctx, $message, $*args)`,

		`Logger.Error($ctx, $message, $*args)`,
		`Logger.Warn($ctx, $message, $*args)`,
		`Logger.Info($ctx, $message, $*args)`,
		`Logger.Debug($ctx, $message, $*args)`,

		`$foo.Logger.Error($ctx, $message, $*args)`,
		`$foo.Logger.Warn($ctx, $message, $*args)`,
		`$foo.Logger.Info($ctx, $message, $*args)`,
		`$foo.Logger.Debug($ctx, $message, $*args)`,
	).
		Where(
			(
			// It doesn't end with a special character:
			m["message"].Text.Matches(`[.!?]"$`) ||
				// it starts with lowercase:
				m["message"].Text.Matches(`^"[A-Z]{1}`) &&
					// but there are exceptions:
					!m["message"].Text.Matches(`^"Prometheus`) &&
					!m["message"].Text.Matches(`^"X11`) &&
					!m["message"].Text.Matches(`^"CSP`) &&
					!m["message"].Text.Matches(`^"OIDC`))).
		Report(`Message $message must start with lowercase, and does not end with a special characters.`)
}

// slogMessageLength ensures that important log messages are meaningful, and must be at least 16 characters long.
func slogMessageLength(m dsl.Matcher) {
	m.Import("cdr.dev/slog")
	m.Match(
		`logger.Error($ctx, $message, $*args)`,
		`logger.Warn($ctx, $message, $*args)`,
		`logger.Info($ctx, $message, $*args)`,

		`$foo.logger.Error($ctx, $message, $*args)`,
		`$foo.logger.Warn($ctx, $message, $*args)`,
		`$foo.logger.Info($ctx, $message, $*args)`,

		`Logger.Error($ctx, $message, $*args)`,
		`Logger.Warn($ctx, $message, $*args)`,
		`Logger.Info($ctx, $message, $*args)`,

		`$foo.Logger.Error($ctx, $message, $*args)`,
		`$foo.Logger.Warn($ctx, $message, $*args)`,
		`$foo.Logger.Info($ctx, $message, $*args)`,

		// no debug
	).
		Where(
			// It has at least 16 characters (+ ""):
			m["message"].Text.Matches(`^".{0,15}"$`) &&
				// but there are exceptions:
				!m["message"].Text.Matches(`^"command exit"$`)).
		Report(`Message $message is too short, it must be at least 16 characters long.`)
}

// slogErr ensures that errors are logged with "slog.Error" instead of "slog.F"
func slogError(m dsl.Matcher) {
	m.Import("cdr.dev/slog")
	m.Match(
		`slog.F($name, $value)`,
	).
		Where(m["name"].Const && m["value"].Type.Is("error") && !m["name"].Text.Matches(`^"internal_error"$`)).
		Report(`Error should be logged using "slog.Error" instead.`)
}

// withTimezoneUTC ensures that we don't just sprinkle dbtestutil.WithTimezone("UTC") about
// to work around real timezone bugs in our code.
//
//nolint:unused,deadcode,varnamelen
func withTimezoneUTC(m dsl.Matcher) {
	m.Match(
		`dbtestutil.WithTimezone($tz)`,
	).Where(
		m["tz"].Text.Matches(`[uU][tT][cC]"$`),
	).Report(`Setting database timezone to UTC may mask timezone-related bugs.`).
		At(m["tz"])
}
