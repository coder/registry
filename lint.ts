import { readFile, readdir, stat } from "node:fs/promises";
import * as path from "node:path";
import * as marked from "marked";
import grayMatter from "gray-matter";

const files = await readdir(".", { withFileTypes: true });
const dirs = files.filter((f) => {
  return (
    f.isDirectory() && !f.name.startsWith(".") && f.name !== "node_modules"
  );
});

let badExit = false;

// error reports an error to the console and sets badExit to true
// so that the process will exit with a non-zero exit code.
const error = (...data: readonly unknown[]) => {
  console.error(...data);
  badExit = true;
};

const verifyCodeBlocks = (
  tokens: readonly marked.Token[],
  res = {
    codeIsTF: false,
    codeIsHCL: false,
  },
) => {
  for (const token of tokens) {
    // Check in-depth.
    if (token.type === "list") {
      verifyCodeBlocks(token.items, res);
      continue;
    }

    if (token.type === "list_item") {
      if (token.tokens === undefined) {
        throw new Error("Tokens are missing for type list_item");
      }

      verifyCodeBlocks(token.tokens, res);
      continue;
    }

    if (token.type === "code") {
      if (token.lang === "tf") {
        res.codeIsTF = true;
      }
      if (token.lang === "hcl") {
        res.codeIsHCL = true;
      }
    }
  }
  return res;
};

// Ensures that each README has the proper format.
// Exits with 0 if all is good!
for (const dir of dirs) {
  const readme = path.join(dir.name, "README.md");
  // Ensure exists
  try {
    await stat(readme);
  } catch (ex) {
    throw new Error(`Missing README.md in ${dir.name}`);
  }
  const content = await readFile(readme, "utf8");
  const matter = grayMatter(content);
  const data = matter.data as {
    display_name?: string;
    description?: string;
    icon?: string;
    maintainer_github?: string;
    partner_github?: string;
    verified?: boolean;
    tags?: string[];
  };
  if (!data.display_name) {
    error(dir.name, "missing display_name");
  }
  if (!data.description) {
    error(dir.name, "missing description");
  }
  if (!data.icon) {
    error(dir.name, "missing icon");
  }
  if (!data.maintainer_github) {
    error(dir.name, "missing maintainer_github");
  }

  try {
    await stat(path.join(".", dir.name, data.icon ?? ""));
  } catch (ex) {
    error(dir.name, "icon does not exist", data.icon);
  }

  const tokens = marked.lexer(content);
  // Ensure there is an h1 and some text, then a code block

  let h1 = false;
  let code = false;
  let paragraph = false;
  let version = true;

  for (const token of tokens) {
    if (token.type === "heading" && token.depth === 1) {
      h1 = true;
      continue;
    }
    if (h1 && token.type === "heading") {
      break;
    }
    if (token.type === "paragraph") {
      paragraph = true;
      continue;
    }
    if (token.type === "code") {
      code = true;
      if (token.lang === "tf" && !token.text.includes("version")) {
        version = false;
        error(dir.name, "missing version in tf code block");
      }
    }
  }
  if (!h1) {
    error(dir.name, "missing h1");
  }
  if (!paragraph) {
    error(dir.name, "missing paragraph after h1");
  }
  if (!code) {
    error(dir.name, "missing example code block after paragraph");
  }

  const { codeIsTF, codeIsHCL } = verifyCodeBlocks(tokens);
  if (!codeIsTF) {
    error(dir.name, "missing example tf code block");
  }
  if (codeIsHCL) {
    error(dir.name, "hcl code block should be tf");
  }
}

if (badExit) {
  process.exit(1);
}
