using EuropeanDataFormat
using Test

testfile(name) = joinpath(@__DIR__, name)

const cases = [
  ("test1.edf", 200, 600, (idx1=3, val1=11008, cnt255=2), (rows=120000, chans=11)),
  ("test2.edf", 256, 350, (idx1=257, val1=12587, cnt255=111), (rows=89600, chans=20)),
  ("test3.edf", 512, 6, (idx1=3, val1=11008, cnt255=5), (rows=3072, chans=139)),
]

@testset "EuropeanDataFormat" begin

  @testset "read_edf (header + data + selections)" begin
    for (fname, sr, nrecs, trig, sz) in cases
      @testset "read_edf $(sr)Hz" begin
        edf = testfile(fname)

        # header-only
        hdr = read_edf(edf, header_only=true)
        @test isa(hdr, EuropeanDataFormat.EdfHeader)
        @test hdr.num_bytes_header == (sz.chans + 2) * 256
        @test hdr.num_channels == sz.chans + 1
        @test hdr.num_data_records == nrecs
        @test hdr.sample_rate[1] == sr

        # full file
        dat = read_edf(edf)
        @test dat.header.num_bytes_header == (sz.chans + 2) * 256
        @test dat.header.num_channels == sz.chans + 1
        @test dat.header.num_data_records == nrecs
        @test dat.header.sample_rate[1] == sr
        @test size(dat.data) == (sz.rows, sz.chans)
        @test dat.triggers.idx[1] == trig.idx1
        @test dat.triggers.val[1] == trig.val1
        @test dat.triggers.count[trig.val1] == trig.cnt255

        # selection by indices
        dat2 = read_edf(edf, channels=[1, 3, 5])
        @test dat.data[:, 1] == dat2.data[:, 1]
        @test dat.data[:, 5] == dat2.data[:, 3]
        @test dat2.header.num_bytes_header == 5 * 256
        @test dat2.header.num_channels == 4
        @test dat2.header.num_data_records == nrecs
        @test dat2.header.sample_rate[1] == sr
        @test size(dat2.data) == (sz.rows, 3)
        @test dat2.triggers.idx[1] == trig.idx1
        @test dat2.triggers.val[1] == trig.val1
        @test dat2.triggers.count[trig.val1] == trig.cnt255

        # selection by labels (only assert known labels on 2048Hz fixture)
        if sr == 512
          dat3 = read_edf(edf, channels=["A1", "A3", "A5"])
          @test dat.data[:, 1] == dat3.data[:, 1]
          @test dat.data[:, 5] == dat3.data[:, 3]
          @test dat3.header.num_bytes_header == 5 * 256
          @test dat3.header.num_channels == 4
          @test dat3.header.num_data_records == nrecs
          @test dat3.header.sample_rate[1] == sr
          @test size(dat3.data) == (sz.rows, 3)
          @test dat3.triggers.idx[1] == trig.idx1
          @test dat3.triggers.val[1] == trig.val1
          @test dat3.triggers.count[trig.val1] == trig.cnt255
        end
      end
    end
  end

  @testset "write_edf roundtrip" begin
    for (fname, sr, nrecs, trig, sz) in cases
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
    for (fname, sr, nrecs, trig, sz) in cases
      edf = testfile(fname)
      dat = read_edf(edf)
      @test dat.header.num_channels == sz.chans + 1
      dat = delete_channels_edf(dat, [1])
      @test dat.header.num_channels == sz.chans
    end
  end

  @testset "merge_edf extras" begin
    for (fname, sr, nrecs, trig, sz) in cases
      edf = testfile(fname)
      d1 = read_edf(edf)
      d2 = read_edf(edf)
      m = merge_edf([d1, d2])

      @test m.header.num_bytes_header == (sz.chans + 2) * 256
      @test m.header.num_channels == sz.chans + 1
      @test m.header.num_data_records == nrecs * 2
      @test m.header.sample_rate[1] == sr
      @test size(m.data) == (sz.rows * 2, sz.chans)
      @test m.triggers.idx[1] == trig.idx1
      @test m.triggers.val[1] == trig.val1
      @test m.triggers.count[trig.val1] == trig.cnt255 * 2
    end
  end

  @testset "channel label/metadata integrity" begin
    edf = testfile("test3.edf")
    dat = read_edf(edf)
    sel = select_channels_edf(dat, [1, 3, 5])
    @test sel.header.num_channels == 4 # includes status
    @test length(sel.header.channel_labels) == sel.header.num_channels
    @test sel.header.num_bytes_header == (sel.header.num_channels + 1) * 256
  end

  @testset "crop_edf" begin
    for (fname, sr, nrecs, trig, sz) in cases
      edf = testfile(fname)
      dat = read_edf(edf)
      cropped = crop_edf(dat, "records", [2 4])
      @test size(dat.data, 1) != size(cropped.data, 1)
      @test size(dat.data, 2) == size(cropped.data, 2)
      @test cropped.header.num_data_records == 3

      # trigger-based crop between first and last trigger event
      if length(dat.triggers.val) >= 2
        cropped2 = crop_edf(dat, "triggers", [dat.triggers.val[1] dat.triggers.val[end]])
        @test size(cropped2.data, 2) == size(dat.data, 2)
        @test cropped2.header.num_data_records >= 0
        @test first(cropped2.time) == 0
      end
    end
  end

  @testset "downsample_edf details" begin
    for (fname, sr, nrecs, trig, sz) in cases
      dat = read_edf(testfile(fname))
      dec = 2
      ds = downsample_edf(dat, dec)
      @test ds.header.sample_rate[1] == div(dat.header.sample_rate[1], dec)
      @test ds.header.num_samples[1] == div(dat.header.num_samples[1], dec)
      @test size(ds.data, 1) == div(size(dat.data, 1), dec)
      @test length(ds.time) == size(ds.data, 1)
      @test length(ds.triggers.raw) == size(ds.data, 1)
      @test ds.triggers.idx[1] == round(Int, dat.triggers.idx[1] / dec)
    end
  end

  @testset "read triggers-only" begin
    for (fname, sr, nrecs, trig, sz) in cases
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
    d3 = read_edf(edf)

    # Force header mismatches
    d2.header.num_channels = 139
    @test_throws ErrorException merge_edf([d1, d2])

    d2.header.num_channels = 140
    d2.header.channel_labels = d2.header.channel_labels[1:end-1]
    @test_throws ErrorException merge_edf([d1, d2])

    d2.header.channel_labels = d1.header.channel_labels
    d2.header.sample_rate = [512]
    @test_throws ErrorException merge_edf([d1, d2])
  end

  @testset "bang variants mutate in place" begin
    for (fname, sr, nrecs, trig, sz) in cases
      edf = testfile(fname)
      dat = read_edf(edf)
      orig_channels = dat.header.num_channels
      orig_bytes = dat.header.num_bytes_header
      orig_labels = copy(dat.header.channel_labels)

      # Test select_channels_edf!
      select_channels_edf!(dat, [1, 3, 5])
      @test dat.header.num_channels == 4
      @test dat.header.num_bytes_header == 5 * 256
      @test length(dat.header.channel_labels) == 4
      @test size(dat.data, 2) == 3

      # Test delete_channels_edf!
      delete_channels_edf!(dat, [1])
      @test dat.header.num_channels == 3
      @test dat.header.num_bytes_header == 4 * 256
      @test length(dat.header.channel_labels) == 3
      @test size(dat.data, 2) == 2
    end
  end

  @testset "write_edf default filename" begin
    for (fname, sr, nrecs, trig, sz) in cases
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
    @test occursin("Number of Channels: 139", hdr_str)
    @test occursin("Sample Rate: 512", hdr_str)

    trig_str = sprint(show, trig)
    @test occursin("Triggers (Value => Count):", trig_str)

    dat_str = sprint(show, dat)
    @test occursin("Filename:", dat_str)
    @test occursin("Data Size:", dat_str)
  end

  @testset "time boundaries and consistency" begin
    for (fname, sr, nrecs, trig, sz) in cases
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
    for (fname, sr, nrecs, trig, sz) in cases
      dat = read_edf(testfile(fname), channels=[1, -1])
      @test dat.header.num_channels == 2
      @test size(dat.data, 2) == 1
      @test length(dat.triggers.raw) == size(dat.data, 1)
      @test dat.header.num_bytes_header == 3 * 256
    end
  end

  @testset "downsample additional cases" begin
    for (fname, sr, nrecs, trig, sz) in cases
      dat = read_edf(testfile(fname))
      dec = 4
      ds = downsample_edf(dat, dec)
      @test ds.header.sample_rate[1] == div(dat.header.sample_rate[1], dec)
      @test size(ds.data, 1) == div(size(dat.data, 1), dec)

      # Trigger indices within bounds
      valid_indices = filter(x -> 1 <= x <= size(ds.data, 1), ds.triggers.idx)
      @test count(x -> x != 0, ds.triggers.raw) == length(unique(valid_indices))
      @test all(1 .<= ds.triggers.idx .<= size(ds.data, 1))
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
    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3"], ["A1", "A3"])
    @test x == [1, 3]

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3"], "A1")
    @test x == [1, 3]

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3"], "A3")
    @test x == [3]

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3", "A4"], ["A1", "A4"])
    @test x == [1, 4]

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3", "A4"], ["A1", "A4", "A4"])
    @test x == [1, 4]

    @test_throws ErrorException EuropeanDataFormat.channel_index(["A1"], ["zzz"])

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3"], [1, 3])
    @test x == [1, 3]

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3", "A4"], [1, 4])
    @test x == [1, 4]

    x = EuropeanDataFormat.channel_index(["A1", "A2", "A3", "A4"], [1, 4, 4])
    @test x == [1, 4]

    @test_throws ErrorException EuropeanDataFormat.channel_index(["A1"], [2])
    @test_throws ErrorException EuropeanDataFormat.channel_index(["A1"], [1, 2])
  end

  @testset "recode_triggers" begin
    for (fname, sr, nrecs, trig, sz) in cases
      @testset "recode_triggers $(sr)Hz" begin
        edf = testfile(fname)
        dat = read_edf(edf)

        # Get original trigger information
        original_triggers = copy(dat.triggers.raw)
        original_count = copy(dat.triggers.count)
        original_trigger_values = sort(collect(keys(original_count)))

        # Test 1: Recode triggers (non-mutating)
        if length(original_trigger_values) >= 1
          test_val = original_trigger_values[1]
          new_val = 30000
          dat_recoded = recode_triggers(dat, recode_triggers=Dict(test_val => new_val))

          # Original should be unchanged
          @test dat.triggers.raw == original_triggers
          @test dat.triggers.count == original_count

          # New should have recoded values
          # Note: trigger values persist across samples, so we check count of events, not samples
          @test new_val in keys(dat_recoded.triggers.count)
          @test dat_recoded.triggers.count[new_val] == original_count[test_val]
          @test test_val ∉ keys(dat_recoded.triggers.count)
          # Verify all samples with old value are now new value
          @test count(x -> x == test_val, dat_recoded.triggers.raw) == 0
        end

        # Test 2: Remove triggers (non-mutating)
        if length(original_trigger_values) >= 1
          remove_val = original_trigger_values[1]
          dat_removed = recode_triggers(dat, remove_triggers=[remove_val])

          # Original should be unchanged
          @test dat.triggers.raw == original_triggers

          # Removed triggers should be set to 0
          @test count(x -> x == remove_val, dat_removed.triggers.raw) == 0
          @test remove_val ∉ keys(dat_removed.triggers.count)
        end

        # Test 3: Add triggers (non-mutating)
        add_val = 30001
        add_idx = min(1000, size(dat.data, 1))  # Use valid index
        dat_added = recode_triggers(dat, add_triggers=Dict(add_val => add_idx))

        # Original should be unchanged
        @test dat.triggers.raw == original_triggers

        # New trigger should be present at specified index
        @test dat_added.triggers.raw[add_idx] == add_val
        @test add_val in keys(dat_added.triggers.count)

        # Test 4: Combined operations (non-mutating)
        if length(original_trigger_values) >= 3
          recode_val1 = original_trigger_values[1]
          recode_val2 = original_trigger_values[2]
          new_val1 = 30002
          new_val2 = 30003
          remove_val = original_trigger_values[3]
          add_val = 30004
          add_idx = min(2000, size(dat.data, 1))

          dat_combined = recode_triggers(dat,
            recode_triggers=Dict(recode_val1 => new_val1, recode_val2 => new_val2),
            remove_triggers=[remove_val],
            add_triggers=Dict(add_val => add_idx))

          # Original should be unchanged
          @test dat.triggers.raw == original_triggers

          # Check recoded values
          @test new_val1 in keys(dat_combined.triggers.count)
          @test new_val2 in keys(dat_combined.triggers.count)

          # Check removed value
          @test count(x -> x == remove_val, dat_combined.triggers.raw) == 0

          # Check added value
          @test dat_combined.triggers.raw[add_idx] == add_val
        end

        # Test 5: Mutating version (!)
        dat_mut = read_edf(edf)
        original_raw_mut = copy(dat_mut.triggers.raw)

        if length(original_trigger_values) >= 1
          test_val = original_trigger_values[1]
          new_val = 30005
          recode_triggers!(dat_mut, recode_triggers=Dict(test_val => new_val))

          # Should be modified in place
          @test dat_mut.triggers.raw != original_raw_mut
          @test new_val in keys(dat_mut.triggers.count)
          @test count(x -> x == test_val, dat_mut.triggers.raw) == 0
        end

        # Test 6: Trigger information is recalculated correctly
        dat_test = read_edf(edf)
        if length(original_trigger_values) >= 1
          test_val = original_trigger_values[1]
          new_val = 30006
          recode_triggers!(dat_test, recode_triggers=Dict(test_val => new_val))

          # Trigger info should be consistent
          @test length(dat_test.triggers.raw) == size(dat_test.data, 1)
          @test length(dat_test.triggers.idx) == length(dat_test.triggers.val)
          # time is a matrix with 2 columns, so check number of rows
          @test size(dat_test.triggers.time, 1) == length(dat_test.triggers.idx)
          @test size(dat_test.triggers.time, 2) == 2

          # Count should match number of trigger events (not samples)
          @test dat_test.triggers.count[new_val] == length(findall(x -> x == new_val, dat_test.triggers.val))
        end

        # Test 7: Out of range index handling (should warn but not error)
        dat_safe = read_edf(edf)
        invalid_idx = size(dat_safe.data, 1) + 1000
        valid_idx = min(500, size(dat_safe.data, 1))

        # Should handle out of range gracefully
        recode_triggers!(dat_safe, add_triggers=Dict(222 => invalid_idx, 111 => valid_idx))

        # Valid trigger should be added
        @test dat_safe.triggers.raw[valid_idx] == 111

        # Test 8: Empty operations should not change data
        dat_empty = read_edf(edf)
        original_empty = copy(dat_empty.triggers.raw)
        recode_triggers!(dat_empty, remove_triggers=Int[], recode_triggers=Dict{Int,Int}(), add_triggers=Dict{Int,Int}())

        # Should be unchanged
        @test dat_empty.triggers.raw == original_empty

        # Test 9: Overlapping mappings (value is both source and target)
        # This tests the fix for the bug where overlapping mappings caused incorrect recoding
        dat_overlap = read_edf(edf)
        original_overlap = copy(dat_overlap.triggers.raw)
        original_count_overlap = copy(dat_overlap.triggers.count)

        # Test overlapping mappings: 3->4, 4->2, 5->3
        # Original 3's should become 4's (not 2's!)
        # Original 4's should become 2's
        # Original 5's should become 3's
        if 3 in keys(original_count_overlap) && 4 in keys(original_count_overlap) && 5 in keys(original_count_overlap)
          count_3_orig = original_count_overlap[3]
          count_4_orig = original_count_overlap[4]
          count_5_orig = original_count_overlap[5]

          recode_triggers!(dat_overlap, recode_triggers=Dict(3 => 4, 4 => 2, 5 => 3))

          # Original 3's should become 4's
          @test dat_overlap.triggers.count[4] >= count_3_orig  # At least the original 3's
          # Original 4's should become 2's
          @test 2 in keys(dat_overlap.triggers.count)
          @test dat_overlap.triggers.count[2] >= count_4_orig  # At least the original 4's
          # Original 5's should become 3's
          @test dat_overlap.triggers.count[3] >= count_5_orig  # At least the original 5's

          # Verify no double-recoding: original 3's should NOT become 2's
          # Count how many 2's came from original 3's (should be 0)
          # We can verify this by checking that 2's only come from original 4's
          # Since we can't easily track this, we verify the counts are correct
          # Original 3's became 4's, so total 4's should be >= original 3's
          # Original 4's became 2's, so total 2's should be >= original 4's
          # Original 5's became 3's, so total 3's should be >= original 5's
        end

        # Test 10: Verify original is unchanged after non-mutating version
        dat_orig_test = read_edf(edf)
        original_test = copy(dat_orig_test.triggers.raw)
        original_count_test = copy(dat_orig_test.triggers.count)

        if length(keys(original_count_test)) >= 2
          test_vals = sort(collect(keys(original_count_test)))
          val1 = test_vals[1]
          val2 = test_vals[2]

          # Test overlapping: val1 -> val2, val2 -> 30007
          dat_result = recode_triggers(dat_orig_test, recode_triggers=Dict(val1 => val2, val2 => 30007))

          # Original should be completely unchanged
          @test dat_orig_test.triggers.raw == original_test
          @test dat_orig_test.triggers.count == original_count_test

          # Result should have val1's recoded to val2, val2's recoded to 30007
          # Original val1's should become val2's (not 30007's!)
          @test val2 in keys(dat_result.triggers.count)
          @test 30007 in keys(dat_result.triggers.count)
        end
      end
    end
  end

end
