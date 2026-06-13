-- rex.lua — Neovim configuration for Rex language support
-- Place this in ~/.config/nvim/after/plugin/rex.lua  (or require from init.lua)
--
-- Prerequisites:
--   - nvim-lspconfig  (https://github.com/neovim/nvim-lspconfig)
--   - `rex` binary on PATH  (sudo make install)
--
-- Features enabled:
--   - .rex filetype detection
--   - Syntax highlighting (via LSP semantic tokens)
--   - LSP: diagnostics, completion, hover, go-to-definition,
--          signature help, rename, formatting

-- ─── Filetype detection ───────────────────────────────────────────────────────
vim.filetype.add({
    extension = { rex = "rex" },
})

-- ─── Basic syntax rules (fallback before semantic tokens kick in) ─────────────
vim.api.nvim_create_autocmd("FileType", {
    pattern = "rex",
    callback = function()
        -- Tab settings
        vim.bo.tabstop     = 4
        vim.bo.shiftwidth  = 4
        vim.bo.expandtab   = true
        vim.bo.commentstring = "// %s"
    end,
})

-- ─── LSP configuration via nvim-lspconfig ────────────────────────────────────
local ok, lspconfig = pcall(require, "lspconfig")
if not ok then
    vim.notify("rex.lua: nvim-lspconfig not found. Install it to enable LSP features.", vim.log.levels.WARN)
    return
end

local configs = require("lspconfig.configs")

-- Register rex-lsp as a custom server
if not configs.rex_lsp then
    configs.rex_lsp = {
        default_config = {
            cmd          = { "rex", "lsp" },
            filetypes    = { "rex" },
            root_dir     = lspconfig.util.root_pattern("rex.toml", ".git") or vim.fn.getcwd,
            settings     = {},
            capabilities = vim.lsp.protocol.make_client_capabilities(),
            init_options = {},
            name         = "rex_lsp",
        },
        docs = {
            description  = "Rex language server (rex lsp)",
            default_config = { cmd = { "rex", "lsp" } },
        },
    }
end

-- ─── On-attach: key mappings ──────────────────────────────────────────────────
local function on_attach(client, bufnr)
    local opts = { buffer = bufnr, noremap = true, silent = true }

    -- Go-to-definition
    vim.keymap.set("n", "gd",         vim.lsp.buf.definition,      opts)
    -- Hover documentation
    vim.keymap.set("n", "K",          vim.lsp.buf.hover,           opts)
    -- Signature help
    vim.keymap.set("i", "<C-k>",      vim.lsp.buf.signature_help,  opts)
    -- Rename symbol
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename,          opts)
    -- Format document
    vim.keymap.set("n", "<leader>f",  function()
        vim.lsp.buf.format({ async = true })
    end, opts)
    -- Show diagnostics for current line
    vim.keymap.set("n", "<leader>e",  vim.diagnostic.open_float,   opts)
    -- Navigate diagnostics
    vim.keymap.set("n", "[d",         vim.diagnostic.goto_prev,    opts)
    vim.keymap.set("n", "]d",         vim.diagnostic.goto_next,    opts)

    -- Format on save
    if client.supports_method("textDocument/formatting") then
        vim.api.nvim_create_autocmd("BufWritePre", {
            buffer   = bufnr,
            callback = function()
                vim.lsp.buf.format({ bufnr = bufnr, async = false })
            end,
        })
    end
end

-- ─── Start the server ─────────────────────────────────────────────────────────
lspconfig.rex_lsp.setup({
    on_attach    = on_attach,
    capabilities = (function()
        local caps = vim.lsp.protocol.make_client_capabilities()
        -- Enable snippet support for completion
        caps.textDocument.completion.completionItem.snippetSupport = true
        return caps
    end)(),
})

-- ─── Optional: tree-sitter grammar (if installed) ────────────────────────────
-- Uncomment and install the grammar if you have nvim-treesitter:
--   :TSInstall rex   (once a grammar is published)
-- local ts_ok, ts_configs = pcall(require, "nvim-treesitter.configs")
-- if ts_ok then
--     ts_configs.setup({ ensure_installed = { "rex" } })
-- end

vim.notify("Rex LSP loaded (rex lsp)", vim.log.levels.INFO)
