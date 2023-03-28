package.path = package.path .. ";./?.tl"
local tl = require('tl')
tl.loader()
require('tlTest')
tl.gen([[
local record test
    number:number
end
]])