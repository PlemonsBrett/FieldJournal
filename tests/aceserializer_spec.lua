local function test_aceserializer_roundtrips_a_table()
    _G.LibStub = nil
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")

    local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
    local input = {name = "Rimurai", count = 3, nested = {"a", "b"}}

    local serialized = AceSerializer:Serialize(input)
    assert(type(serialized) == "string", "Serialize did not return a string")

    local ok, result = AceSerializer:Deserialize(serialized)
    assert(ok, "Deserialize reported failure: " .. tostring(result))
    assert(result.name == "Rimurai", "round-tripped name did not match")
    assert(result.count == 3, "round-tripped count did not match")
    assert(result.nested[1] == "a" and result.nested[2] == "b", "round-tripped nested list did not match")
end

return {
    test_aceserializer_roundtrips_a_table = test_aceserializer_roundtrips_a_table,
}
