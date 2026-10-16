import json
import sys


def strip_jsonc_comments(source):
    result = []
    index = 0
    in_string = False
    escaped = False

    while index < len(source):
        character = source[index]

        if in_string:
            result.append(character)
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            index += 1
            continue

        if character == '"':
            in_string = True
            result.append(character)
            index += 1
            continue

        if character == "/" and index + 1 < len(source):
            next_character = source[index + 1]
            if next_character == "/":
                index += 2
                while index < len(source) and source[index] not in "\r\n":
                    index += 1
                continue
            if next_character == "*":
                result.append(" ")
                index += 2
                while index + 1 < len(source):
                    if source[index : index + 2] == "*/":
                        index += 2
                        break
                    if source[index] in "\r\n":
                        result.append(source[index])
                    index += 1
                else:
                    raise ValueError("unterminated block comment in IDE settings")
                continue

        result.append(character)
        index += 1

    return "".join(result)


def strip_trailing_commas(source):
    result = []
    index = 0
    in_string = False
    escaped = False

    while index < len(source):
        character = source[index]

        if in_string:
            result.append(character)
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            index += 1
            continue

        if character == '"':
            in_string = True
        elif character == ",":
            lookahead = index + 1
            while lookahead < len(source) and source[lookahead].isspace():
                lookahead += 1
            if lookahead < len(source) and source[lookahead] in "}]":
                index += 1
                continue

        result.append(character)
        index += 1

    return "".join(result)


def load_jsonc(path):
    with open(path, encoding="utf-8-sig") as source_file:
        source = source_file.read()
    return json.loads(strip_trailing_commas(strip_jsonc_comments(source)))


def merge(existing, configured):
    result = dict(existing)
    for key, value in configured.items():
        if isinstance(result.get(key), dict) and isinstance(value, dict):
            result[key] = merge(result[key], value)
        else:
            result[key] = value
    return result


existing = load_jsonc(sys.argv[1])
with open(sys.argv[2], encoding="utf-8") as configured_file:
    configured = json.load(configured_file)

if not isinstance(existing, dict):
    raise ValueError("the existing IDE settings file must contain a JSON object")

with open(sys.argv[3], "w", encoding="utf-8") as merged_file:
    json.dump(merge(existing, configured), merged_file, indent=2)
    merged_file.write("\n")
