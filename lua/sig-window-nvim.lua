local function get_active_param_indices(active_param_ix, params, label)
  if params and active_param_ix and active_param_ix >= 0 and active_param_ix < #params then
    local active_param = params[active_param_ix + 1].label

    if type(active_param) == 'table' then
        return unpack(active_param)
    end

    if type(active_param) == 'string' then
      local s, e = string.find(label, active_param, 1, true)
      return (s - 1), e
    end
  end

  return nil, nil
end

local function parse_signature_help_result(lsp_result)
  local sig_idx = (lsp_result.activeSignature or 0) + 1
  local sig = lsp_result.signatures[sig_idx]
  local active_param = sig.activeParameter or lsp_result.activeParameter
  local active_ix_start, active_ix_end = get_active_param_indices(active_param, sig.parameters, sig.label)
  local other_labels = {}
  for i, sigx in ipairs(lsp_result.signatures) do
      if i ~= sig_idx then
          table.insert(other_labels, sigx.label)
      end
  end
  return sig.label, sig.parameters, active_ix_start, active_ix_end, other_labels
end

local function highlight_text(bufnr, start_ix, end_ix, highlight_group)
  vim.api.nvim_buf_clear_namespace(bufnr, -1, 0, -1)
  if start_ix and end_ix then
    vim.api.nvim_buf_add_highlight(bufnr, 0, highlight_group, 0, start_ix, end_ix)
  end
end

local function calc_window_dimensions(lines, max_width, max_height)
  text = table.concat(lines, "\n")

  local length = string.len(text)
  if length <= max_width then
    return length, 1
  end

  local height = math.ceil(length / max_width)
  if height > max_height then
    return max_width, max_height
  end

  return max_width, height
end

local function window_config(label, config, width, height, other_labels)
    if config.window_config then
      return config.window_config(label, config, width, height, other_labels)
    end

    return {
      relative = 'editor',
      anchor = 'NE',
      width = width,
      height = height,
      row = 0,
      col = vim.api.nvim_win_get_width(0),
      focusable = false,
      zindex = config.zindex,
      style = 'minimal',
      border = config.border,
    }
end

local function close_signature_window(bufnr)
  local sig_window = vim.F.npcall(vim.api.nvim_buf_get_var, bufnr, 'sig-window-nvim')
  if sig_window and vim.api.nvim_win_is_valid(sig_window) then
    vim.api.nvim_win_close(sig_window, true)
  end
end

local function show_signature_window(label, active_ix_start, active_ix_end, config, other_labels)
  local bufnr = vim.api.nvim_get_current_buf()
  local w_bufnr = vim.api.nvim_create_buf(false, true)

  table.insert(other_labels, 1, label)  -- put activeSignature label the first line
  vim.api.nvim_buf_set_lines(w_bufnr, 0, -1, true, other_labels)
  highlight_text(w_bufnr, active_ix_start, active_ix_end, config.hl_group)

  local lines = other_labels
  local width, height = calc_window_dimensions(lines, config.max_width, config.max_height)
  local winnr = vim.api.nvim_open_win(w_bufnr, false, window_config(label, config, width, height, other_labels))
  close_signature_window(bufnr)

  vim.api.nvim_win_set_option(winnr, 'wrap', true)
  vim.api.nvim_win_set_option(winnr, 'foldenable', false)
  vim.api.nvim_buf_set_option(w_bufnr, 'filetype', vim.bo[bufnr].filetype)
  vim.api.nvim_buf_set_option(w_bufnr, 'modifiable', false)
  vim.api.nvim_buf_set_option(w_bufnr, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_var(bufnr, 'sig-window-nvim', winnr)

  return w_bufnr
end

module = {
  default_config = {
    zindex = 50,
    border = 'rounded',
    max_width = 80,
    max_height = 5,
    hl_active_param = true,
    hl_group = 'DiagnosticWarn',
  },
  config = {},
  previous_label = '',
  previous_active_ix_start = -1,
  previous_active_ix_end = -1,
  window_bufnr = -1,
  is_open = false,
}

function module.signature_help_handler(_, result, _, config)
  if result and result.signatures and result.signatures[1] and vim.fn.mode() == 'i' then
    local label, _, active_ix_start, active_ix_end, other_labels = parse_signature_help_result(result)
    if label ~= module.previous_label or not module.is_open then
      module.previous_label = label
      module.previous_active_ix_start = active_ix_start
      module.previous_active_ix_end = active_ix_end
      module.window_bufnr = show_signature_window(label, active_ix_start, active_ix_end, config, other_labels)
      module.is_open = true
    elseif active_ix_start ~= module.previous_active_ix_start or active_ix_end ~= module.previous_active_ix_end then
      module.previous_active_ix_start = active_ix_start
      module.previous_active_ix_end = active_ix_end
      highlight_text(module.window_bufnr, active_ix_start, active_ix_end, config.hl_group)
    end
  elseif module.is_open then
    module.is_open = false
    close_signature_window(vim.api.nvim_get_current_buf())
  end
end

function module.close_signature_help()
  if module.is_open then
    module.is_open = false
    close_signature_window(vim.api.nvim_get_current_buf())
  end
end

function module.request_signature_help(opts)
  vim.lsp.buf_request(
    opts.buf,
    'textDocument/signatureHelp',
    vim.lsp.util.make_position_params(),
    vim.lsp.with(module.signature_help_handler, module.config[opts.buf])
  )
end

function module.set_config(bufnr, config)
  config = config or {}
  module.config[bufnr] = {}
  for k, v in pairs(module.default_config) do module.config[bufnr][k] = v end
  for k, v in pairs(config) do module.config[bufnr][k] = v end
end

function module.on_attach(client, bufnr, config)
  if client.server_capabilities.signatureHelpProvider then
    module.set_config(bufnr, config)

    local au_group_name = 'sig_window_nvim_aug_' .. bufnr
    local request_opts = { callback = module.request_signature_help, group = au_group_name, buffer = bufnr }
    local close_opts = { callback = module.close_signature_help, group = au_group_name, buffer = bufnr }
    vim.api.nvim_create_augroup(au_group_name, {clear = true})
    vim.api.nvim_create_autocmd('InsertEnter', request_opts)
    vim.api.nvim_create_autocmd('CursorMovedI', request_opts)
    vim.api.nvim_create_autocmd('InsertLeave', close_opts)
    vim.api.nvim_create_autocmd('BufLeave', close_opts)
    vim.api.nvim_create_autocmd('WinLeave', close_opts)
    vim.api.nvim_create_autocmd('TabLeave', close_opts)
  end
end

function module.setup(swn_config)
  local start_lsp_client = vim.lsp.start_client
  vim.lsp.start_client = function(lsp_config)
    local on_attach = lsp_config.on_attach
    lsp_config.on_attach = function(client, bufnr)
      module.on_attach(client, bufnr, swn_config)
      if on_attach ~= nil then
        on_attach(client, bufnr)
      end
    end
    return start_lsp_client(lsp_config)
  end
end

return module
