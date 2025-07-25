#!/bin/bash

# Mock Codex CLI for testing purposes
# This script simulates the behavior of the actual codex-cli for testing

case "$1" in
  "--version")
    echo "codex-cli 1.0.0"
    ;;
  "complete")
    # Mock completion response
    cat << 'EOF'
{
  "id": "cmpl-test123",
  "object": "text_completion",
  "created": 1234567890,
  "model": "gpt-3.5-turbo-instruct",
  "choices": [
    {
      "text": "\n\nThis is a mock completion response for testing purposes. The actual CLI would interact with OpenAI's API to generate code completions based on the provided prompt.",
      "index": 0,
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 25,
    "total_tokens": 35
  }
}
EOF
    ;;
  "chat")
    # Mock chat response
    cat << 'EOF'
{
  "id": "chatcmpl-test123",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "gpt-3.5-turbo",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "This is a mock chat response for testing. The actual CLI would provide interactive code assistance and explanations."
      },
      "index": 0,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 15,
    "completion_tokens": 20,
    "total_tokens": 35
  }
}
EOF
    ;;
  *)
    echo "Mock Codex CLI - Available commands: complete, chat, --version"
    echo "This is a test mock. In production, this would be replaced with the actual Rust CLI."
    ;;
esac
