# sig-window-nvim

Neovim plugin that displays available lsp signature help in a highly configurable floating window, and highlights active parameters.

This plugin was heavily inspired by [lsp_signature](https://github.com/ray-x/lsp_signature.nvim). If you're looking for a more feature-rich signature window definitely check it out.

![](/screenshots/sig-window-nvim.png)

## Installation

Install manually or with your favorite plugin manager and add the following line to your startup script:

```lua
require('sig-window-nvim').setup({})
```

or use on_attach to provide lsp client specific configurations:

```lua
require('sig-window-nvim').on_attach(client, bufnr, {})
```

## Configuration

A configuration table can be passed to setup as its first argument, or to on_attach as its third argument. Example below uses the default values:

```lua
require('sig-window-nvim').setup({
  zindex = 50,                -- signature window z-index
  border = 'rounded',         -- signature window border, see ':help nvim_open_win' for possible values
  max_width = 80,             -- signature window max width
  max_height = 5,             -- signature window max height
  hl_active_param = true,     -- whether or not to highlight the active parameter
  hl_group = 'rainbowcol4',   -- highlight group used to highlight active parameter
})
```

Additionally, the configuration can contain a function that accepts five arguments:

1. The string to be displayed in the signature window
2. The configuration table specified above, plus its default values.
3. A ui object, see [`:help nvim_list_uis`](https://neovim.io/doc/user/api.html#nvim_list_uis())
4. Width, suggested width based on the signature length and max_width/max_height
5. Height, suggested height based on the signature length and max_width/max_height

The expected return value is a table that will be passed to [nvim_open_win](https://neovim.io/doc/user/api.html#nvim_open_win()) as its configuration. See [`:help nvim_open_win`](https://neovim.io/doc/user/api.html#nvim_open_win()) for more details. The example below displays the default behavior:

```lua
require('sig-window-nvim').setup({
  window_config = function(label, config, ui, width, height)
    return {
      relative = 'editor',
      anchor = 'NE',
      width = width,
      height = height,
      row = 0,
      col = ui.width,
      focusable = false,
      zindex = config.zindex,
      style = 'minimal',
      border = config.border,
    }
  end
})
```

## Caveats

This plugin sends a signatureHelp request to attached language servers on two events, when insert mode is entered, and whenever the cursor moves in insert mode. This is the easiest way to guarantee the window is always be up to date, but at the cost of an unnecessary amount of requests. I have no idea what a reasonable request rate is for most language servers. If you install this plugin, or have it installed and install a new language server, then find your performance has decreased a noticable amount, this plugin may be to blame.
