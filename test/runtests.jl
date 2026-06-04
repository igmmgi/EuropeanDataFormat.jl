using EuropeanDataFormat
using Test

testfile(name) = joinpath(@__DIR__, name)

# Test cases: (filename, sample_rate, num_data_records,
#              (trigger_idx1, trigger_val1, trigger_count_for_val1) or nothing for no triggers,
#              (data_rows, data_cols=EEG channels excl status),
#              num_channels_in_header (includes status if present))
const cases = [
  # test1: EDF+ with EDF Annotations, no Status channel → 11 data channels, no triggers
  ("test1.edf", 200, 600, nothing, (rows=120000, chans=11), 11),
  # test2: EDF+ with EDF Annotations, no Status channel → 20 data channels, no triggers
  ("test2.edf", 256, 350, nothing, (rows=89600, chans=20), 20),
  # test3: EDF+ with EDF Annotations + Status channel → 138 data channels, 13 triggers
  ("test3.edf", 512, 6, (idx1=513, val1=4096, cnt=7), (rows=3072, chans=138), 139),
]

const extended_cases = [
  # test4: EDF+ with EDF Annotations, no Status channel
  ("test4.edf", 200, 18181, (363620, 37), nothing),
  # test5: Plain EDF, no Status/Annotations, mixed sample rates
  ("test5.edf", 200, 900, (180000, 16), nothing),
]

@testset "EuropeanDataFormat" begin

  @testset "read_edf (header + data + selections)" begin
    for (fname, sr, nrecs, trig, sz, nch) in cases
      @testset "read_edf $(sr)Hz" begin
        edf = testfile(fname)

        # header-only
        hdr = read_edf(edf, header_only=true)
        @test isa(hdr, EuropeanDataFormat.EdfHeader)
        @test hdr.num_channels == nch
        @test hdr.num_data_records == nrecs
        @test hdr.sample_rate[1] == sr

        # full file
        dat = read_edf(edf)
        @test dat.header.num_channels == nch
        @test dat.header.num_data_records == nrecs
        @test dat.header.sample_rate[1] == sr
        @test size(dat.data) == (sz.rows, sz.chans)

        if trig !== nothing
          @test dat.triggers.idx[1] == trig.idx1
          @test dat.triggers.val[1] == trig.val1
          @test dat.triggers.count[trig.val1] == trig.cnt
        else
          @test isempty(dat.triggers.idx)
        end

        # selection by indices
        dat2 = read_edf(edf, channels=[1, 3, 5])
        @test dat.data[:, 1] == dat2.data[:, 1]
        @test dat.data[:, 5] == dat2.data[:, 3]
        @test dat2.header.num_data_records == nrecs
        @test dat2.header.sample_rate[1] == sr
        @test size(dat2.data) == (sz.rows, 3)

        if trig !== nothing
          @test dat2.triggers.idx[1] == trig.idx1
          @test dat2.triggers.val[1] == trig.val1
          @test dat2.triggers.count[trig.val1] == trig.cnt
        end

        # selection by labels (test3 has A1-A5 labels)
        if sr == 512
          dat3 = read_edf(edf, channels=["A1", "A3", "A5"])
          @test dat.data[:, 1] == dat3.data[:, 1]
          @test dat.data[:, 5] == dat3.data[:, 3]
          @test dat3.header.num_data_records == nrecs
          @test dat3.header.sample_rate[1] == sr
          @test size(dat3.data) == (sz.rows, 3)
          @test dat3.triggers.idx[1] == trig.idx1
          @test dat3.triggers.val[1] == trig.val1
          @test dat3.triggers.count[trig.val1] == trig.cnt
        end
      end
    end
  end

  @testset "write_edf roundtrip" begin
    for (fname, sr, nrecs, trig, sz, nch) in cases
      mktempdir() do tmp
        src = testfile(fname)
        dat1 = read_edf(src)
        out = joinpath(tmp, "out.edf")
        write_edf(dat1, out)
        dat2 = read_edf(out)

        @test dat1.data == dat2.data
        @test dat1.status == dat2.status
        @test dat1.time == dat2.time
        @test dat1.triggers.count == dat2.triggers.count
        @test dat1.triggers.idx == dat2.triggers.idx
        @test dat1.triggers.raw == dat2.triggers.raw
        @test dat1.triggers.time == dat2.triggers.time
        @test dat1.triggers.val == dat2.triggers.val
      end
    end
  end

  @testset "delete_channels_edf" begin
    for (fname, sr, nrecs, trig, sz, nch) in cases
      edf = testfile(fname)
      dat = read_edf(edf)
      @test dat.header.num_channels == nch
      dat = delete_channels_edf(dat, [1])
      @test dat.header.num_channels == nch - 1
      @test size(dat.data, 2) == sz.chans - 1
    end
  end

  @testset "merge_edf extras" begin
    for (fname, sr, nrecs, trig, sz, nch) in cases
      edf = testfile(fname)
      d1 = read_edf(edf)
      d2 = read_edf(edf)
      m = merge_edf([d1, d2])

      @test m.header.num_channels == nch
      @test m.header.num_data_records == nrecs * 2
      @test m.header.sample_rate[1] == sr
      @test size(m.data) == (sz.rows * 2, sz.chans)

      if trig !== nothing
        @test m.triggers.idx[1] == trig.idx1
        @test m.triggers.val[1] == trig.val1
        @test m.triggers.count[trig.val1] == trig.cnt * 2
      end
    end
  end

  @testset "channel label/metadata integrity" begin
    edf = testfile("test3.edf")
    dat = read_edf(edf)
    sel = select_channels_edf(dat, [1, 3, 5])
    @test sel.header.num_channels == 4 # 3 data + status
    @test length(sel.header.channel_labels) == sel.header.num_channels
  end

  @testset "crop_edf" begin
    for (fname, sr, nrecs, trig, sz, nch) in cases
      edf = testfile(fname)
      dat = read_edf(edf)
      cropped = crop_edf(dat, "records", [2 4])
      @test size(dat.data, 1) != size(cropped.data, 1)
      @test size(dat.data, 2) == size(cropped.data, 2)
      @test cropped.header.num_data_records == 3

      # trigger-based crop between first and last trigger event
      if !isempty(dat.triggers.val) && length(dat.triggers.val) >= 2
        cropped2 = crop_edf(dat, "triggers", [dat.triggers.val[1] dat.triggers.val[end]])
        @test size(cropped2.data, 2) == size(dat.data, 2)
        @test cropped2.header.num_data_records >= 0
        @test first(cropped2.time) == 0
      end
    end
  end

  @testset "downsample_edf details" begin
    for (fname, sr, nrecs, trig, sz, nch) in cases
      dat = read_edf(testfile(fname))
      dec = 2
      ds = downsample_edf(dat, dec)
      @test ds.header.sample_rate[1] == div(dat.header.sample_rate[1], dec)
      @test ds.header.num_samples[1] == div(dat.header.num_samples[1], dec)
      @test size(ds.data, 1) == div(size(dat.data, 1), dec)
      @test length(ds.time) == size(ds.data, 1)
      @test length(ds.triggers.raw) == size(ds.data, 1)
      if trig !== nothing && trig.idx1 > 0
        @test ds.triggers.idx[1] == round(Int, dat.triggers.idx[1] / dec)
      end
    end
  end

  @testset "read triggers-only" begin
    for (fname, sr, nrecs, trig, sz, nch) in cases
      dat = read_edf(testfile(fname), channels=[-1])
      @test size(dat.data, 2) == 0
      @test length(dat.triggers.raw) == length(dat.time)
    end
  end

  @testset "errors" begin
    @test_throws ErrorException read_edf(testfile("does_not_exist.edf"))
    dat = read_edf(testfile("test3.edf"))
    @test_throws ErrorException downsample_edf(dat, 3)
    @test_throws ErrorException crop_edf(dat, "invalid", [1 2])
    @test_throws ErrorException crop_edf(dat, "records", [1])
    @test_throws ErrorException crop_edf(dat, "records", [0 20])
    @test_throws ErrorException crop_edf(dat, "records", [10 61])
    @test_throws ErrorException crop_edf(dat, "triggers", [999 1000])
  end

  @testset "merge_edf error paths" begin
    edf = testfile("test3.edf")
    d1 = read_edf(edf)
    d2 = read_edf(edf)

    # Force header mismatches
    d2.header.num_channels = 138
    @test_throws ErrorException merge_edf([d1, d2])

    d2.header.num_channels = 139
    d2.header.channel_labels = d2.header.channel_labels[1:end-1]
    @test_throws ErrorException merge_edf([d1, d2])

    d2.header.channel_labels = d1.header.channel_labels
    d2.header.sample_rate = [512]
    @test_throws ErrorException merge_edf([d1, d2])
  end

  @testset "bang variants mutate in place" begin
    for (fname, sr, nrecs, trig, sz, nch) in cases
      edf = testfile(fname)
      dat = read_edf(edf)

      # Test select_channels_edf!
      select_channels_edf!(dat, [1, 3, 5])
      has_status = "Status" in dat.header.channel_labels
      expected_header_chans = has_status ? 4 : 3
      @test dat.header.num_channels == expected_header_chans
      @test length(dat.header.channel_labels) == expected_header_chans
      @test size(dat.data, 2) == 3

      # Test delete_channels_edf!
      delete_channels_edf!(dat, [1])
      expected_header_chans2 = has_status ? 3 : 2
      @test dat.header.num_channels == expected_header_chans2
      @test length(dat.header.channel_labels) == expected_header_chans2
      @test size(dat.data, 2) == 2
    end
  end

  @testset "write_edf default filename" begin
    for (fname, sr, nrecs, trig, sz, nch) in cases
      mktempdir() do tmp
        src = testfile(fname)
        dat = read_edf(src)
        out = joinpath(tmp, "out.edf")
        dat.filename = out
        write_edf(dat)  # No filename arg
        @test isfile(out)
        dat2 = read_edf(out)
        @test dat.data == dat2.data
      end
    end
  end

  @testset "Base.show methods" begin
    edf = testfile("test3.edf")
    hdr = read_edf(edf, header_only=true)
    dat = read_edf(edf)
    trig = dat.triggers

    hdr_str = sprint(show, hdr)
    @test occursin("Number of Channels: 138", hdr_str)
    @test occursin("Sample Rate: 512", hdr_str)

    trig_str = sprint(show, trig)
    @test occursin("Triggers (Value => Count):", trig_str)

    dat_str = sprint(show, dat)
    @test occursin("Filename:", dat_str)
    @test occursin("Data Size:", dat_str)
  end

  @testset "time boundaries and consistency" begin
    for (fname, sr, nrecs, trig, sz, nch) in cases
      dat = read_edf(testfile(fname))
      @test length(dat.time) == size(dat.data, 1)
      @test last(dat.time) == (nrecs - 1 / sr)
      @test first(dat.time) == 0

      # After cropping
      cropped = crop_edf(dat, "records", [2 4])
      @test length(cropped.time) == size(cropped.data, 1)
      @test cropped.header.num_data_records == 3
    end
  end

  @testset "mixed channel selection including status" begin
    # Only test on files that have a Status channel
    edf = testfile("test3.edf")
    dat = read_edf(edf, channels=[1, -1])
    @test size(dat.data, 2) == 1
    @test length(dat.triggers.raw) == size(dat.data, 1)
    @test dat.header.num_channels == 2

    # For files without Status, -1 is a no-op
    edf1 = testfile("test1.edf")
    dat1 = read_edf(edf1, channels=[1, -1])
    @test size(dat1.data, 2) == 1
    @test isempty(dat1.triggers.idx)
  end

  @testset "downsample additional cases" begin
    for (fname, sr, nrecs, trig, sz, nch) in cases
      dat = read_edf(testfile(fname))
      dec = 4
      ds = downsample_edf(dat, dec)
      @test ds.header.sample_rate[1] == div(dat.header.sample_rate[1], dec)
      @test size(ds.data, 1) == div(size(dat.data, 1), dec)

      # Trigger indices within bounds
      valid_indices = filter(x -> 1 <= x <= size(ds.data, 1), ds.triggers.idx)
      @test count(x -> x != 0, ds.triggers.raw) == length(unique(valid_indices))
      if !isempty(ds.triggers.idx)
        @test all(1 .<= ds.triggers.idx .<= size(ds.data, 1))
      end
    end
  end

  @testset "header parsing robustness" begin
    edf = testfile("test3.edf")
    dat = read_edf(edf)
    sel = select_channels_edf(dat, [1, 3, 5])

    # Header field lengths track channel selections
    @test length(sel.header.channel_labels) == sel.header.num_channels
    @test length(sel.header.transducer_type) == sel.header.num_channels
    @test length(sel.header.channel_unit) == sel.header.num_channels
    @test length(sel.header.physical_min) == sel.header.num_channels
    @test length(sel.header.physical_max) == sel.header.num_channels
    @test length(sel.header.digital_min) == sel.header.num_channels
    @test length(sel.header.digital_max) == sel.header.num_channels
    @test length(sel.header.pre_filter) == sel.header.num_channels
    @test length(sel.header.num_samples) == sel.header.num_channels
    @test length(sel.header.reserved) == sel.header.num_channels
    @test length(sel.header.sample_rate) == sel.header.num_channels
    @test length(sel.header.scale_factor) == sel.header.num_channels
  end

  @testset "channel_index" begin
    # With status channel (last element = status)
    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3", "Status"], ["A1", "A3"], 4)
    @test x == [1, 3, 4]

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3", "Status"], "A1", 4)
    @test x == [1, 4]

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3", "Status"], "A3", 4)
    @test x == [3, 4]

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3", "A4", "Status"], ["A1", "A4"], 5)
    @test x == [1, 4, 5]

    @test_throws ErrorException EuropeanDataFormat.channel_index(["A1"], ["zzz"], 0)

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3", "Status"], [1, 3], 4)
    @test x == [1, 3, 4]

    # Without status channel
    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3"], ["A1", "A3"], 0)
    @test x == [1, 3]

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3"], [1, 3], 0)
    @test x == [1, 3]

    # -1 with status
    x = EuropeanDataFormat.channel_index(["A1", "A2", "Status"], [-1], 3)
    @test x == [3]

    # -1 without status (no-op)
    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3"], [-1], 0)
    @test isempty(x)

    @test_throws ErrorException EuropeanDataFormat.channel_index(["A1"], [2], 0)
  end

  @testset "recode_triggers" begin
    # Only test on files with triggers (test3)
    fname = "test3.edf"
    @testset "recode_triggers 512Hz" begin
      edf = testfile(fname)
      dat = read_edf(edf)

      # Get original trigger information
      original_triggers = copy(dat.triggers.raw)
      original_count = copy(dat.triggers.count)
      original_trigger_values = sort(collect(keys(original_count)))

      # Test 1: Recode triggers (non-mutating)
      @test length(original_trigger_values) >= 1
      test_val = original_trigger_values[1]
      new_val = 30000
      dat_recoded = recode_triggers(dat, recode_triggers=Dict(test_val => new_val))

      # Original should be unchanged
      @test dat.triggers.raw == original_triggers
      @test dat.triggers.count == original_count

      # New should have recoded values
      @test new_val in keys(dat_recoded.triggers.count)
      @test dat_recoded.triggers.count[new_val] == original_count[test_val]
      @test test_val ∉ keys(dat_recoded.triggers.count)
      @test count(x -> x == test_val, dat_recoded.triggers.raw) == 0

      # Test 2: Remove triggers (non-mutating)
      remove_val = original_trigger_values[1]
      dat_removed = recode_triggers(dat, remove_triggers=[remove_val])

      @test dat.triggers.raw == original_triggers
      @test count(x -> x == remove_val, dat_removed.triggers.raw) == 0
      @test remove_val ∉ keys(dat_removed.triggers.count)

      # Test 3: Add triggers (non-mutating)
      add_val = 30001
      add_idx = min(1000, size(dat.data, 1))
      dat_added = recode_triggers(dat, add_triggers=Dict(add_val => add_idx))

      @test dat.triggers.raw == original_triggers
      @test dat_added.triggers.raw[add_idx] == add_val
      @test add_val in keys(dat_added.triggers.count)

      # Test 4: Combined operations (non-mutating)
      if length(original_trigger_values) >= 2
        recode_val1 = original_trigger_values[1]
        recode_val2 = original_trigger_values[2]
        new_val1 = 30002
        new_val2 = 30003
        add_val = 30004
        add_idx = min(2000, size(dat.data, 1))

        dat_combined = recode_triggers(dat,
          recode_triggers=Dict(recode_val1 => new_val1, recode_val2 => new_val2),
          add_triggers=Dict(add_val => add_idx))

        @test dat.triggers.raw == original_triggers
        @test new_val1 in keys(dat_combined.triggers.count)
        @test new_val2 in keys(dat_combined.triggers.count)
        @test dat_combined.triggers.raw[add_idx] == add_val
      end

      # Test 5: Mutating version (!)
      dat_mut = read_edf(edf)
      original_raw_mut = copy(dat_mut.triggers.raw)
      test_val = original_trigger_values[1]
      new_val = 30005
      recode_triggers!(dat_mut, recode_triggers=Dict(test_val => new_val))

      @test dat_mut.triggers.raw != original_raw_mut
      @test new_val in keys(dat_mut.triggers.count)
      @test count(x -> x == test_val, dat_mut.triggers.raw) == 0

      # Test 6: Trigger information is recalculated correctly
      dat_test = read_edf(edf)
      test_val = original_trigger_values[1]
      new_val = 30006
      recode_triggers!(dat_test, recode_triggers=Dict(test_val => new_val))

      @test length(dat_test.triggers.raw) == size(dat_test.data, 1)
      @test length(dat_test.triggers.idx) == length(dat_test.triggers.val)
      @test size(dat_test.triggers.time, 1) == length(dat_test.triggers.idx)
      @test size(dat_test.triggers.time, 2) == 2
      @test dat_test.triggers.count[new_val] == length(findall(x -> x == new_val, dat_test.triggers.val))

      # Test 7: Out of range index handling
      dat_safe = read_edf(edf)
      invalid_idx = size(dat_safe.data, 1) + 1000
      valid_idx = min(500, size(dat_safe.data, 1))
      recode_triggers!(dat_safe, add_triggers=Dict(222 => invalid_idx, 111 => valid_idx))
      @test dat_safe.triggers.raw[valid_idx] == 111

      # Test 8: Empty operations should not change data
      dat_empty = read_edf(edf)
      original_empty = copy(dat_empty.triggers.raw)
      recode_triggers!(dat_empty, remove_triggers=Int[], recode_triggers=Dict{Int,Int}(), add_triggers=Dict{Int,Int}())
      @test dat_empty.triggers.raw == original_empty

      # Test 9: Verify original is unchanged after non-mutating version
      dat_orig_test = read_edf(edf)
      original_test = copy(dat_orig_test.triggers.raw)
      original_count_test = copy(dat_orig_test.triggers.count)

      if length(keys(original_count_test)) >= 2
        test_vals = sort(collect(keys(original_count_test)))
        val1 = test_vals[1]
        val2 = test_vals[2]

        dat_result = recode_triggers(dat_orig_test, recode_triggers=Dict(val1 => val2, val2 => 30007))

        @test dat_orig_test.triggers.raw == original_test
        @test dat_orig_test.triggers.count == original_count_test
        @test val2 in keys(dat_result.triggers.count)
        @test 30007 in keys(dat_result.triggers.count)
      end
    end
  end

  @testset "EDF Annotations handling" begin
    # test1 has EDF Annotations but no Status channel
    dat1 = read_edf(testfile("test1.edf"))
    @test !("EDF Annotations" in dat1.header.channel_labels)
    @test isempty(dat1.triggers.idx)
    @test dat1.header.num_channels == 11

    # test3 has both EDF Annotations and Status channel
    dat3 = read_edf(testfile("test3.edf"))
    @test !("EDF Annotations" in dat3.header.channel_labels)
    @test "Status" in dat3.header.channel_labels
    @test length(dat3.triggers.idx) == 13
    @test dat3.triggers.val[1] == 4096
  end

  @testset "Extended EDF file reading" begin
    for (fname, sr, nrecs, sz, trig) in extended_cases
      dat = read_edf(testfile(fname))
      @test dat.header.sample_rate[1] == sr
      @test dat.header.num_data_records == nrecs
      @test size(dat.data) == sz

      if isnothing(trig)
        @test isempty(dat.triggers.idx)
      else
        @test dat.triggers.idx[1] == trig.idx1
        @test dat.triggers.val[1] == trig.val1
      end
    end
  end

end
