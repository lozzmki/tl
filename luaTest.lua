package.path = package.path .. ";./?.tl"
local tl = require('tl')
tl.loader()
require('tlTest')
local result, err = tl.gen([[
local record baseC
    basenum: number
end
local record test
    implements baseC
    testNum:number
end
]])

print(result)

function f(t, depth)
    depth = depth or 0
    if depth > 3 then
        return
    end
    for k,v in pairs(t or {}) do
        if(type(v) == "table") then
            f(v, depth + 1)
        else
            indent = {}
            for i = 1, depth do
                table.insert(indent, '\t')
            end
            table.insert(indent,k)
            table.insert(indent,'\t')
            table.insert(indent,v)
            s = ""
            for _, item in ipairs(indent) do
                s=s..tostring(item)
            end
            print(s)
        end
    end
end

-- f(err)