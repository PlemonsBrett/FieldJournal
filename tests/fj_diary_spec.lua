local env = dofile("tests/wow_env.lua")

local function load()
    return env.loadModules({"Core/Bootstrap.lua", "Data/Diary.lua"})
end

local function test_add_batch_item_accumulates_counts_and_skips_blanks()
    local fj = load()
    local batch = {items = {}}
    fj.Diary.addBatchItem(batch, "  Copper Ore  ", 2)
    fj.Diary.addBatchItem(batch, "Copper Ore", 3)
    fj.Diary.addBatchItem(batch, "Tin Ore", nil)
    fj.Diary.addBatchItem(batch, "   ", 9)
    assert(batch.items["Copper Ore"] == 5, "counts for the same trimmed name must accumulate")
    assert(batch.items["Tin Ore"] == 1, "a missing count must default to 1")
    assert(batch.items[""] == nil, "a blank name must be ignored")
end

local function test_item_summary_sorts_and_joins()
    local fj = load()
    assert(fj.Diary.itemSummary({}) == "", "an empty item set summarises as an empty string")
    local summary = fj.Diary.itemSummary({["Tin Ore"] = 2, ["Copper Ore"] = 5})
    assert(summary == "2 × Tin Ore, 5 × Copper Ore",
        "itemSummary sorts the rendered strings, got: " .. summary)
end

local function test_batch_section_maps_every_kind()
    local fj = load()
    local expected = {merchant = "TRADE", training = "TRAINING", group = "COMPANY",
        gather = "GATHERING", craft = "CRAFTING", skill = "SKILLS", milestone = "SKILLS",
        purchase = "OTHER MEMORIES"}
    for kind, section in pairs(expected) do
        assert(fj.Diary.batchSection({kind = kind}) == section,
            "batchSection(" .. kind .. ") should be " .. section)
    end
end

local function test_batch_description_renders_each_batch_kind()
    local fj = load()
    assert(fj.Diary.batchDescription({kind = "gather", place = "the Glade",
        items = {["Copper Ore"] = 2}}) == "Near the Glade, I gathered 2 × Copper Ore.",
        "gather wording changed")
    assert(fj.Diary.batchDescription({kind = "craft", place = "the forge",
        items = {["Rough Stone"] = 1}}) == "At the forge, I made 1 × Rough Stone.",
        "craft wording changed")
    local trade = fj.Diary.batchDescription({kind = "merchant", place = "Ironforge",
        vendor = "Grum", sold = {["Pelt"] = 2}, bought = {}, received = 10001, spent = 0})
    assert(trade == "At Ironforge, I traded with Grum.\nSold: 2 × Pelt.\nReceived 1 gold, 1 copper.",
        "merchant wording changed, got: " .. trade)
    local other = fj.Diary.batchDescription({kind = "training",
        raw = {{body = "first line"}, {title = "second line"}}})
    assert(other == "first line\nsecond line", "fallback wording changed, got: " .. other)
end

local function test_merchant_items_splits_the_body_and_totals_coin()
    local fj = load()
    local batch = {sold = {}, bought = {}, spent = 0, received = 0}
    fj.Diary.merchantItems(batch, {kind = "purchase",
        body = "At Ironforge, I bought 2 Linen Cloth, 1 Silk Cloth from Grum for 1 gold, 5 silver."})
    assert(batch.bought["Linen Cloth"] == 2, "purchased quantities were not parsed")
    assert(batch.bought["Silk Cloth"] == 1, "the second purchased item was not parsed")
    assert(batch.spent == 10500, "the spent amount was not totalled, got " .. batch.spent)

    fj.Diary.merchantItems(batch, {kind = "sale",
        body = "At Ironforge, I sold 3 Wolf Pelt to Grum for 20 copper."})
    assert(batch.sold["Wolf Pelt"] == 3, "sold quantities were not parsed")
    assert(batch.received == 20, "the received amount was not totalled, got " .. batch.received)
end

local function test_group_life_events_batches_by_window_and_key()
    local fj = load()
    local batches = fj.Diary.groupLifeEvents({
        {key = "craft:1", kind = "craft", place = "the forge", title = "Crafted Bronze Bar",
            seenAt = 1000, order = 1, count = 1},
        {key = "craft:2", kind = "craft", place = "the forge", title = "Crafted Bronze Bar",
            seenAt = 1060, order = 2, count = 2},
        {key = "craft:3", kind = "craft", place = "the forge", title = "Crafted Bronze Bar",
            seenAt = 9000, order = 3, count = 1},
    })
    assert(#batches == 2, "two crafts inside the 180s window are one batch, got " .. #batches)
    assert(batches[1].items["Bronze Bar"] == 3, "batched counts must add up")
    assert(batches[2].items["Bronze Bar"] == 1, "a craft outside the window starts a new batch")
end

return {
    test_add_batch_item_accumulates_counts_and_skips_blanks = test_add_batch_item_accumulates_counts_and_skips_blanks,
    test_item_summary_sorts_and_joins = test_item_summary_sorts_and_joins,
    test_batch_section_maps_every_kind = test_batch_section_maps_every_kind,
    test_batch_description_renders_each_batch_kind = test_batch_description_renders_each_batch_kind,
    test_merchant_items_splits_the_body_and_totals_coin = test_merchant_items_splits_the_body_and_totals_coin,
    test_group_life_events_batches_by_window_and_key = test_group_life_events_batches_by_window_and_key,
}
