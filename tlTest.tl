local record test
    numf: number
end
function test:testFunc()
    print("testFunc")
end
local record test2
    -- implements test
    tt:test
    num2: number
end
local t:test2 = setmetatable({}, {__index=test2})
-- t:testFunc()
print("Hello from tl in lua require")

local type aliass = integer
local type aliasss = aliass
local x: aliasss = 0
local function f(p: integer)
    print(p)
end
f(x)

local test11 = "asdf"
local asdtg = {
    NO = 1,
    YES = 2,
    COMR = "asdf"
}
