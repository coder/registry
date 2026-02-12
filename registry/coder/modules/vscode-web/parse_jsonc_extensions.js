// Parses a JSONC file and prints extension recommendations, one per line.
// Handles // comments, /* */ block comments (including multi-line), and trailing commas.
// Used by code-server and vscode-web modules to parse .vscode/extensions.json
// and .code-workspace files.
//
// Environment variables:
//   FILE  - path to the JSONC file
//   QUERY - jq-style query: "recommendations" (default) or "extensions.recommendations"
var fs = require("fs");
var text = fs.readFileSync(process.env.FILE, "utf8");
var result = "";
var inString = false;
var pendingComma = "";
var i = 0;

while (i < text.length) {
  if (inString) {
    if (text[i] === "\\" && i + 1 < text.length) {
      result += text.slice(i, i + 2);
      i += 2;
      continue;
    }
    if (text[i] === '"') inString = false;
    result += text[i++];
  } else {
    if (text[i] === '"') {
      inString = true;
      result += pendingComma + text[i++];
      pendingComma = "";
      continue;
    }
    if (text[i] === "/" && text[i + 1] === "/") {
      while (i < text.length && text[i] !== "\n") i++;
      continue;
    }
    if (text[i] === "/" && text[i + 1] === "*") {
      i += 2;
      while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) i++;
      i += 2;
      continue;
    }
    if (text[i] === ",") {
      pendingComma = ",";
      i++;
      continue;
    }
    if (
      pendingComma &&
      (text[i] === " " ||
        text[i] === "\t" ||
        text[i] === "\n" ||
        text[i] === "\r")
    ) {
      pendingComma += text[i++];
      continue;
    }
    if (text[i] === "]" || text[i] === "}") {
      pendingComma = "";
    }
    result += pendingComma + text[i++];
    pendingComma = "";
  }
}
var data = JSON.parse(result);
var query = process.env.QUERY || "recommendations";
var recommendations;
if (query === "extensions.recommendations") {
  recommendations = (data.extensions && data.extensions.recommendations) || [];
} else {
  recommendations = data.recommendations || [];
}
recommendations.forEach(function (e) {
  console.log(e);
});
