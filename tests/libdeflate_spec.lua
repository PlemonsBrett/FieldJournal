local function test_libdeflate_compress_and_encode_roundtrip()
    _G.LibStub = nil
    dofile("Libs/LibStub/LibStub.lua")
    dofile("Libs/LibDeflate/LibDeflate.lua")

    local LibDeflate = LibStub:GetLibrary("LibDeflate")
    local input = "Field Journal export smoke test"

    local compressed = LibDeflate:CompressDeflate(input)
    assert(type(compressed) == "string", "CompressDeflate did not return a string")

    local decompressed = LibDeflate:DecompressDeflate(compressed)
    assert(decompressed == input, "decompressed text did not match the original input")

    local encoded = LibDeflate:EncodeForPrint(compressed)
    assert(type(encoded) == "string", "EncodeForPrint did not return a string")

    local decoded = LibDeflate:DecodeForPrint(encoded)
    assert(decoded == compressed, "decoded text did not match the original compressed bytes")
end

return {
    test_libdeflate_compress_and_encode_roundtrip = test_libdeflate_compress_and_encode_roundtrip,
}
