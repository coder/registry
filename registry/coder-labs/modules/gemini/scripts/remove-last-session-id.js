const path = require("path")
const fs = require("fs")

const workingDirArg = process.argv[2]
if (!workingDirArg) {
  console.log("No working directory provided - it must be the first argument")
  process.exit(1)
}

const workingDir = path.resolve(workingDirArg)
console.log("workingDir", workingDir)

const geminiConfigLocations = [
  path.join(process.env.HOME, ".gemini", "session.json"),
  path.join(process.env.HOME, ".gemini", "config.json"),
  path.join(workingDir, ".gemini", "session.json"),
  path.join(workingDir, ".gemini", "config.json")
]

let configFound = false

for (const configPath of geminiConfigLocations) {
  console.log("Checking gemini config path:", configPath)
  if (fs.existsSync(configPath)) {
    configFound = true
    try {
      const configJson = JSON.parse(fs.readFileSync(configPath, "utf8"))
      
      let modified = false
      
      if ("lastSessionId" in configJson) {
        delete configJson.lastSessionId
        modified = true
      }
      
      if ("session" in configJson && "lastSessionId" in configJson.session) {
        delete configJson.session.lastSessionId
        modified = true
      }
      
      if ("projects" in configJson && workingDir in configJson.projects && "lastSessionId" in configJson.projects[workingDir]) {
        delete configJson.projects[workingDir].lastSessionId
        modified = true
      }
      
      if (modified) {
        fs.writeFileSync(configPath, JSON.stringify(configJson, null, 2))
        console.log("Removed lastSessionId from", configPath)
      } else {
        console.log("No lastSessionId found in", configPath, "- nothing to do")
      }
    } catch (error) {
      console.log("Error processing", configPath, ":", error.message)
    }
  }
}

if (!configFound) {
  console.log("No gemini config files found - nothing to do")
}

process.exit(0)