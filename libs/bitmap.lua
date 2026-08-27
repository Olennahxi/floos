--[[
* Lua bitmap helper (from XIUI / RexmecK Lua-Bitmap)
* https://github.com/RexmecK/Lua-Bitmap
* https://github.com/tirem/XIUI — GNU GPL v3
]]--

local function newData()
    local data = {};
    data.bytes = '';

    function data:append(n, byteSize)
        if not byteSize then byteSize = 1; end

        local bytes = '';
        local h = string.format('%0' .. (byteSize * 2) .. 'X', n);
        for i = 1, byteSize do
            local id = (i - 1) * 2;
            bytes = string.char(tonumber(h:sub(id + 1, id + 2), 16)) .. bytes;
        end
        self.bytes = self.bytes .. bytes;
    end

    function data:appendBytes(...)
        local b = '';
        for i = 1, #({ ... }) do
            b = b .. string.char(({ ... })[i]);
        end
        self.bytes = self.bytes .. b;
    end

    function data:appendBegin(n, byteSize)
        if not byteSize then byteSize = 1; end

        local bytes = '';
        local h = string.format('%0' .. (byteSize * 2) .. 'X', n);
        for i = 1, byteSize do
            local id = (i - 1) * 2;
            bytes = string.char(tonumber(h:sub(id + 1, id + 2), 16)) .. bytes;
        end
        self.bytes = bytes .. self.bytes;
    end

    function data:size()
        return self.bytes:len();
    end

    return data;
end

local bitmap = {};
bitmap.size = { 0, 0 };
bitmap.map = {};

function bitmap:new(x, y)
    local newbitmap = {};
    for i, v in pairs(self) do
        newbitmap[i] = v;
    end
    newbitmap.size = { x, y };

    for sx = 1, x do
        newbitmap.map[sx] = {};
        for sy = 1, y do
            newbitmap.map[sx][sy] = { 0, 0, 0, 0 };
        end
    end
    return newbitmap;
end

function bitmap:setPixelColor(x, y, color)
    if not self.map[x] or not self.map[x][y] then
        error('Out of bounds (' .. x .. ', ' .. y .. ') with size: (' .. self.size[1] .. ', ' .. self.size[2] .. ')');
    end
    self.map[x][y] = color;
end

function bitmap:binary()
    local pixelData = {};
    for y = 1, self.size[2] do
        for x = 1, self.size[1] do
            local color = self.map[x][y];
            pixelData[#pixelData + 1] = string.char(math.min(math.max(color[3], 0), 255));
            pixelData[#pixelData + 1] = string.char(math.min(math.max(color[2], 0), 255));
            pixelData[#pixelData + 1] = string.char(math.min(math.max(color[1], 0), 255));
            pixelData[#pixelData + 1] = string.char(math.min(math.max(color[4], 0), 255));
        end
    end

    local infoHeaderData = newData();
    infoHeaderData:append(self.size[1], 4);
    infoHeaderData:append(self.size[2], 4);
    infoHeaderData:append(1, 2);
    infoHeaderData:append(32, 2);
    infoHeaderData:append(3, 4);
    infoHeaderData:append(32, 4);
    infoHeaderData:append(2835, 4);
    infoHeaderData:append(2835, 4);
    infoHeaderData:append(0, 4);
    infoHeaderData:append(0, 4);
    infoHeaderData:appendBytes(0, 0, 255, 0);
    infoHeaderData:appendBytes(0, 255, 0, 0);
    infoHeaderData:appendBytes(255, 0, 0, 0);
    infoHeaderData:appendBytes(0, 0, 0, 255);
    infoHeaderData:appendBytes(32, 110, 105, 87);
    infoHeaderData:append(0, 36);
    infoHeaderData:append(0, 4);
    infoHeaderData:append(0, 4);
    infoHeaderData:append(0, 4);
    infoHeaderData:appendBegin(infoHeaderData:size() + 4, 4);

    local headerData = newData();
    headerData:appendBytes(string.byte('B'), string.byte('M'));
    headerData:append(infoHeaderData:size() + #pixelData + 14, 4);
    headerData:append(0, 2);
    headerData:append(0, 2);
    headerData:append(headerData:size() + infoHeaderData:size() + 4, 4);

    return headerData.bytes .. infoHeaderData.bytes .. table.concat(pixelData);
end

return bitmap;
