// If lastSessionId is present in .claude.json, claude --continue will start a
// conversation starting from that session. The problem is that lastSessionId
// doesn't always point to the last session. The field is updated by claude only
// at the point of normal CLI exit. If Claude exits with an error, or if the user
// restarts the Coder workspace, lastSessionId will be stale, and claude --continue
// will start from an old session.
//
// If lastSessionId is missing, claude seems to accurately figure out where to
// start using the conversation history - even if the CLI previously exited with
// an error.
//
// This script removes the lastSessionId field from .claude.json.
const path = require("path")
const fs = require("fs")

const workingDirArg = process.argv[2]
if (!workingDirArg) {
  console.log("No working directory provided - it must be the first argument")
  process.exit(1)
}

const workingDir = path.resolve(workingDirArg)
console.log("workingDir", workingDir)


const claudeJsonPath = path.join(process.env.HOME, ".claude.json")
console.log(".claude.json path", claudeJsonPath)
if (!fs.existsSync(claudeJsonPath)) {
  console.log("No .claude.json file found")
  process.exit(0)
}

const claudeJson = JSON.parse(fs.readFileSync(claudeJsonPath, "utf8"))
if ("projects" in claudeJson && workingDir in claudeJson.projects && "lastSessionId" in claudeJson.projects[workingDir]) {
  delete claudeJson.projects[workingDir].lastSessionId
  fs.writeFileSync(claudeJsonPath, JSON.stringify(claudeJson, null, 2))
  console.log("Removed lastSessionId from .claude.json")
} else {
  console.log("No lastSessionId found in .claude.json - nothing to do")
}
