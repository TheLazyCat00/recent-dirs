local M = {}

local filepath = vim.fn.stdpath("data") .. "/recent-dirs"

local function save_cwd()
	local lines = vim.fn.readfile(filepath)

	local cwd = vim.fn.getcwd():gsub("\\", "/")
	local cur_buf_path = vim.api.nvim_buf_get_name(0):gsub("\\", "/")
	local line_data = cwd .. "" .. cur_buf_path
	for i, value in ipairs(lines) do
		if value:match("(.-)") == cwd then
			table.remove(lines, i)
			break
		end
	end

	table.insert(lines, 1, line_data)
	vim.fn.writefile(lines, filepath)
end

---@return snacks.picker.Config
local function recent_dirs()
	return {
		finder = function ()
			local lines = vim.fn.readfile(filepath)

			local items = {}
			for i, line in ipairs(lines) do
				local path = line:match("(.-)")
				local buffer = line:match("(.*)")

				table.insert(items, {
					file = path,
					text = path,
					dir = true,
					buffer = buffer,
				})
			end
			return items
		end,
		actions = {
			---@param picker snacks.Picker
			---@param item snacks.picker.Item
			confirm = function(picker, item)
				picker:close()
				if not item then
					return
				end

				M.open_buffer(item.idx)

				save_cwd()
			end,
			---@param picker snacks.Picker
			---@param item snacks.picker.Item
			delete = function(picker, item)
				local done = {}
				local deleted = {}

				local lines = vim.fn.readfile(filepath)
				table.remove(lines, item.idx)
				vim.fn.writefile(lines, filepath)

				deleted["idx"] = item.idx
				picker:find({
					on_done = function()
						if picker:count() == 0 then
							picker:close()
						else
							for _, it in ipairs(picker.list.items) do
								done[#done + 1] = it.idx
							end
							if not vim.tbl_contains(done, deleted.idx) then
								item.idx = item.idx - 1
							end
							picker.list:view(item.idx)
						end
					end,
				})
			end
		},
		win = {
			input = {
				keys = {
					["<c-x>"] = { "delete", mode = { "n", "i" } },
				},
			},
		},
		format = Snacks.picker.format.file,
		preview = Snacks.picker.preview.file,
		title = "Recent Dirs"
	}
end

function M.open_buffer(idx)
	local lines = vim.fn.readfile(filepath)
	if lines[idx] then
		local line = lines[idx]

		local path = line:match("(.-)")
		local buffer = line:match("(.*)")
		vim.fn.chdir(path)
		vim.cmd("edit " .. buffer)

		local bufs = vim.api.nvim_list_bufs()
		for _, bufnr in ipairs(bufs) do
			if bufnr ~= vim.api.nvim_get_current_buf() then

				-- Check if the buffer is valid and listed before attempting to delete
				if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_get_option_value("buflisted", { buf = bufnr }) then
					-- Attempt to delete the buffer.
					-- `force = false` (default) prevents deleting buffers with unsaved changes.
					-- To discard changes and delete, you can set `force = true`.
					-- pcall is used to silently ignore errors if a buffer can't be deleted (e.g., unsaved changes with force=false).
					pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
				end
			end
		end
	end
end

function M.open_dir(idx)
	local lines = vim.fn.readfile(filepath)
	if lines[idx] then
		local line = lines[idx]

		local path = line:match("(.-)")
		vim.fn.chdir(path)
	end
end

function M.load_recent()
	M.open_dir(1)
end

function M.pick()
	Snacks.picker.pick(recent_dirs())
end

function M.setup()
end

local uv = vim.uv

--- Ensure a file exists, creating parent dirs and optionally initializing it
--- @param path string: Full path to the file
--- @param init_content string|nil: Optional content for initialization
local function create_file_if_missing(path, init_content)
	init_content = init_content or ""

	-- Ensure parent directory exists
	local dir = vim.fn.fnamemodify(path, ":h")
	if uv.fs_stat(dir) == nil then
		vim.fn.mkdir(dir, "p")
	end

	-- Create file if it doesn’t exist
	if uv.fs_stat(path) == nil then
		local fd, err = uv.fs_open(path, "w", 420)
		if not fd then
			vim.notify("Failed to create file: " .. path .. " (" .. err .. ")", vim.log.levels.ERROR)
			return
		end
		uv.fs_write(fd, init_content)
		uv.fs_close(fd)
	end
end

create_file_if_missing(filepath)

vim.api.nvim_create_autocmd("VimLeave", {
	callback = save_cwd
})

vim.api.nvim_create_autocmd("DirChangedPre", {
	callback = save_cwd
})

return M
