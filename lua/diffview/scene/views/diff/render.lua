local config = require("diffview.config")
local hl = require("diffview.hl")
local utils = require("diffview.utils")

---@param comp  RenderComponent
---@param show_path boolean
---@param depth integer|nil
local function render_file(comp, show_path, depth)
  ---@type table
  local file = comp.context

  comp:add_text(file.status .. " ", hl.get_git_hl(file.status))

  if depth then
    comp:add_text(string.rep(" ", depth * 2 + 2))
  end

  local icon, icon_hl = hl.get_file_icon(file.basename, file.extension)
  comp:add_text(icon, icon_hl)
  comp:add_text(file.basename, "DiffviewFilePanelFileName")

  if file.stats then
    if file.stats.additions then
      comp:add_text(" " .. file.stats.additions, "DiffviewFilePanelInsertions")
      comp:add_text(", ")
      comp:add_text(tostring(file.stats.deletions), "DiffviewFilePanelDeletions")
    elseif file.stats.conflicts then
      local has_conflicts = file.stats.conflicts > 0
      comp:add_text(
        " " .. (has_conflicts and file.stats.conflicts or config.get_config().signs.done),
        has_conflicts and "DiffviewFilePanelConflicts" or "DiffviewFilePanelInsertions"
      )
    end
  end

  if file.kind == "conflicting" and not (file.stats and file.stats.conflicts) then
    comp:add_text(" !", "DiffviewFilePanelConflicts")
  end

  if show_path then
    comp:add_text(" " .. file.parent_path, "DiffviewFilePanelPath")
  end

  comp:ln()
end

---@param comp RenderComponent
local function render_file_list(comp)
  for _, file_comp in ipairs(comp.components) do
    render_file(file_comp, true)
  end
end

---@param ctx DirData
---@param tree_options TreeOptions
---@return string
local function get_dir_status_text(ctx, tree_options)
  local folder_statuses = tree_options.folder_statuses

  if folder_statuses == "always" or (folder_statuses == "only_folded" and ctx.collapsed) then
    return ctx.status
  end

  return " "
end

---@param depth integer
---@param comp RenderComponent
local function render_file_tree_recurse(depth, comp)
  local conf = config.get_config()

  if comp.name == "file" then
    render_file(comp, false, depth)
    return
  end
  if comp.name ~= "wrapper" then return end

  local dir = comp.components[1]
  ---@type table
  local ctx = dir.context

  dir:add_text(
    get_dir_status_text(ctx, conf.file_panel.tree_options) .. " ",
    hl.get_git_hl(ctx.status)
  )
  dir:add_text(string.rep(" ", depth * 2))
  dir:add_text(ctx.collapsed and conf.signs.fold_closed or conf.signs.fold_open, "DiffviewNonText")

  if conf.use_icons then
    dir:add_text(
      " " .. (ctx.collapsed and conf.icons.folder_closed or conf.icons.folder_open) .. " ",
      "DiffviewFolderSign"
    )
  end

  dir:add_text(ctx.name, "DiffviewFolderName")
  dir:ln()

  if not ctx.collapsed then
    for i = 2, #comp.components do
      render_file_tree_recurse(depth + 1, comp.components[i])
    end
  end
end

---@param comp RenderComponent
local function render_file_tree(comp)
  for _, c in ipairs(comp.components) do
    render_file_tree_recurse(0, c)
  end
end

---@param listing_style "list"|"tree"
---@param comp RenderComponent
local function render_files(listing_style, comp)
  if listing_style == "list" then
    return render_file_list(comp)
  end
  render_file_tree(comp)
end

---@param panel FilePanel
return function(panel)
  if not panel.render_data then
    return
  end

  panel.render_data:clear()
  local width = panel:get_width()
  if width == -1 then
    local panel_config = panel:get_config()
    width = panel_config.width
  end

  ---@type RenderComponent
  local comp = panel.components.path.comp

  comp:add_line(
    utils.path:shorten(utils.path:vim_fnamemodify(panel.adapter.ctx.toplevel, ":~"), width - 6),
    "DiffviewFilePanelRootPath"
  )

  if #panel.files.conflicting > 0 then
    comp = panel.components.conflicting.title.comp
    comp:add_text("Conflicts ", "DiffviewFilePanelTitle")
    comp:add_text("(" .. #panel.files.conflicting .. ")", "DiffviewFilePanelCounter")
    comp:ln()

    render_files(panel.listing_style, panel.components.conflicting.files.comp)
  end

  comp = panel.components.working.title.comp

  if #panel.files.conflicting > 0 then comp:add_line() end

  comp:add_text("Changes ", "DiffviewFilePanelTitle")
  comp:add_text("(" .. #panel.files.working .. ")", "DiffviewFilePanelCounter")
  comp:ln()

  render_files(panel.listing_style, panel.components.working.files.comp)

  if #panel.files.staged > 0 then
    comp = panel.components.staged.title.comp
    comp:add_line()
    comp:add_text("Staged changes ", "DiffviewFilePanelTitle")
    comp:add_text("(" .. #panel.files.staged .. ")", "DiffviewFilePanelCounter")
    comp:ln()

    render_files(panel.listing_style, panel.components.staged.files.comp)
  end

  if panel.rev_pretty_name or (panel.path_args and #panel.path_args > 0) then
    local extra_info = utils.vec_join({ panel.rev_pretty_name }, panel.path_args or {})

    comp = panel.components.info.title.comp
    comp:add_line()
    comp:add_line("Showing changes for:", "DiffviewFilePanelTitle")

    comp = panel.components.info.entries.comp

    for _, arg in ipairs(extra_info) do
      local relpath = utils.path:relative(arg, panel.adapter.ctx.toplevel)
      if relpath == "" then relpath = "." end
      comp:add_line(utils.path:shorten(relpath, width - 5), "DiffviewFilePanelPath")
    end
  end
end
