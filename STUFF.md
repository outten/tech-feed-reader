# Stuff

Random stuff to add to the application.

## [x] CLAUDE_API_KEY

I added my Claude API Key and Name to the .credentials file. Can you integrate and create tests to make sure it works? Implement how it will be used in the application. Also, add a Chat Widget to the application that uses it. Put a chat button on each page at the bottom right that will show a panel for chatting with the context of the page.

Done in commits `bded707` (widget + Chat::Claude module + 22 specs) and `d130a17` (default-closed CSS fix). Verified end-to-end: real PONG round-trip + grounded answer using article excerpt as page context.

## [x] White Listed Shell Actions

I am constantly being asked to approve safe commands like curl, echo, etc. Can you check the VS Code settings for Claude to whitelist all simple shell commands. You did this in a prior commit; however, it is not working.
