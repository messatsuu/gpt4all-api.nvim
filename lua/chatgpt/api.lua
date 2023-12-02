local job = require("plenary.job")
local Config = require("chatgpt.config")
local logger = require("chatgpt.common.logger")

local Api = {}

-- API URL
Api.BASE_URL = "http://localhost:4891"
Api.COMPLETIONS_URL = Api.BASE_URL .. "/v1/completions/"
Api.CHAT_COMPLETIONS_URL = Api.BASE_URL .. "/v1/chat/completions"
Api.EDITS_URL = Api.BASE_URL .. "/v1/edits"

function Api.completions(custom_params, cb)
    local params = vim.tbl_extend("keep", custom_params, Config.options.openai_params)
    Api.make_call(Api.COMPLETIONS_URL, params, cb)
end

function Api.chat_completions(custom_params, cb)
    local params = vim.tbl_extend("keep", custom_params, Config.options.openai_params)
    Api.make_call(Api.CHAT_COMPLETIONS_URL, params, cb)
end

function Api.edits(custom_params, cb)
    local params = vim.tbl_extend("keep", custom_params, Config.options.openai_edit_params)
    Api.make_call(Api.EDITS_URL, params, cb)
end

function Api.make_call(url, params, cb)
    -- the OpenAI API only looks at conversation (messages), the gpt4all API instead looks at 'prompt'

    if params["messages"] ~= nil then
        params.prompt = params.messages[#params.messages].content
    end

    TMP_MSG_FILENAME = os.tmpname()
    local f = io.open(TMP_MSG_FILENAME, "w+")
    if f == nil then
        vim.notify("Cannot open temporary message file: " .. TMP_MSG_FILENAME, vim.log.levels.ERROR)
        return
    end
    f:write(vim.fn.json_encode(params))
    f:close()

    -- Set the API endpoint and data
    local api_endpoint = "http://localhost:4891/v1/completions/"
    local api_key = "not_needed_for_a_local_LLM"
    Api.job = job
        :new({
            command = 'curl',
            args = {
                '-X', 'POST',
                '-H', 'Content-Type: application/json',
                '-H', 'Authorization: Bearer ' .. api_key,
                '-d', '@' .. TMP_MSG_FILENAME,
                api_endpoint
            },
            on_exit = vim.schedule_wrap(function(response, exit_code)
                Api.handle_response(response, exit_code, cb)
            end),
            on_stdout = function(_, data)
                print('Stdout:', data)
            end,
            on_stderr = function(_, data)
                print('Stderr:', data)
            end,
        })
        :start()
end

Api.handle_response = vim.schedule_wrap(function(response, exit_code, cb)
    -- os.remove(TMP_MSG_FILENAME)
    if exit_code ~= 0 then
        vim.notify("An Error Occurred ...", vim.log.levels.ERROR)
        cb("ERROR: API Error")
    end

    local result = table.concat(response:result(), "\n")
    local json = vim.fn.json_decode(result)
    if json == nil then
        cb("No Response.")
    elseif json.error then
        cb("// API ERROR: " .. json.error.message)
    else
        local message = json.choices[1].message
        if message ~= nil then
            local response_text = json.choices[1].message.content
            if type(response_text) == "string" and response_text ~= "" then
                cb(response_text, json.usage)
            else
                cb("...")
            end
        else
            local response_text = json.choices[1].text
            if type(response_text) == "string" and response_text ~= "" then
                cb(response_text, json.usage)
            else
                cb("...")
            end
        end
    end
end)

function Api.close()
    if Api.job then
        job:shutdown()
    end
end

function Api.setup()
end

return Api
