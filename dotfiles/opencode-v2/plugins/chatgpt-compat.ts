import type { Plugin } from "@opencode/plugin"

export default {
  id: "dotfiles.chatgpt-effort-compat",
  async setup(ctx) {
    // GPT-6 emits configuration_update items for reasoning-effort changes, but
    // ChatGPT subscription sharing rejects them. Keep the selected effort on
    // the request rather than replaying these prompt-cache optimization markers.
    for (const hook of ["context", "compaction", "generate", "title"] as const) {
      await ctx.session.hook(
        hook,
        (event) => {
          event.messages = event.messages.filter(
            (message) =>
              !(
                message.role === "system" &&
                message.content.length === 1 &&
                message.content[0].type === "effort"
              ),
          )
        },
        { providerID: "openai" },
      )
    }
  },
} satisfies Plugin.Plugin
