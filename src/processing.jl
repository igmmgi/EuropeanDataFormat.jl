# processing.jl - Data processing functions for EuropeanDataFormat

"""
    crop_edf!(edf, crop_type, val)

Reduce the length of EDF data by cropping (in-place).

# Arguments
- `edf::EdfData`: Data structure to modify
- `crop_type::String`: Cropping method
  - `"records"`: Crop by data record numbers
  - `"triggers"`: Crop between trigger events
- `val::Vector{Int}`: Cropping parameters
  - For `"records"`: start_record to end_record (1-based)
  - For `"triggers"`: start_trigger to end_trigger

# Returns
- `Nothing`: Modifies `edf` in-place

# Examples
```julia
# Crop between records 10-20
crop_edf!(dat, "records", [10 20])

# Crop between first occurrence of trigger 1 and last of trigger 2
crop_edf!(dat, "triggers", [1 2])
```

# Notes
- Modifies the original data structure
- Updates header information (num_data_records)
- Recalculates time vector and trigger information
- Records are 1-based indexing
- Use `crop_edf` for non-mutating version

# See also
- `crop_edf`: Non-mutating version
- `downsample_edf!`: Reduce sampling rate
- `merge_edf`: Combine multiple files
"""
function crop_edf!(edf::EdfData, crop_type::String, val::Array{Int})

  @info "Cropping data: $crop_type, $val"
  crop_check(crop_type, val, edf.triggers.count.keys, edf.header.num_data_records)
  sample_rate = edf.header.sample_rate[1]
  nsamples = size(edf.data, 1)
  idxStart, idxEnd = find_crop_index(edf.triggers, crop_type, val, sample_rate, nsamples)

  # crop
  edf.header.num_data_records = Int(((idxEnd - idxStart) + 1) / sample_rate)
  edf.data = edf.data[idxStart:idxEnd, :]
  edf.time = time_range(edf.header.sample_rate[1], edf.header.num_data_records)
  edf.status = edf.status[idxStart:idxEnd]

  # recaculate trigger information
  trig = edf.triggers.raw[idxStart:idxEnd]
  edf.triggers = trigger_info(trig, edf.header.sample_rate[1])

end


"""
    crop_edf(edf_in, crop_type, val)

Reduce the length of EDF data by cropping (non-mutating).

# Arguments
- `edf_in::EdfData`: Input data structure
- `crop_type::String`: Cropping method ("records" or "triggers")
- `val::Vector{Int}`: Cropping parameters

# Returns
- `EdfData`: New cropped data structure

# Examples
```julia
# Crop and get new structure
dat_cropped = crop_edf(dat, "records", [10 20])
dat_cropped = crop_edf(dat, "triggers", [1 2])
```

# Notes
- Returns a new data structure (original unchanged)
- Calls `crop_edf!` internally
- Useful when you want to preserve the original data

# See also
- `crop_edf!`: In-place version
- `downsample_edf`: Reduce sampling rate
"""
function crop_edf(edf_in::EdfData, crop_type::String, val::Array{Int})
  edf_out = deepcopy(edf_in)
  crop_edf!(edf_out, crop_type, val)
  return edf_out
end


"""
    downsample_edf!(edf, dec)

Reduce the sampling rate of EDF data by an integer factor (in-place).

# Arguments
- `edf::EdfData`: Data structure to modify
- `dec::Int`: Downsampling factor (must be power of 2)

# Returns
- `Nothing`: Modifies `edf` in-place

# Examples
```julia
# Downsample by factor of 2
downsample_edf!(dat, 2)

# Downsample by factor of 4
downsample_edf!(dat, 4)

# Check the new sampling rate
println("Original sampling rate: ", dat.header.sample_rate[1], " Hz")
```

# Notes
- Modifies the original data structure
- Applies anti-aliasing filter using DSP.resample
- Reduces data length by factor `dec`
- Updates header information (sample_rate, num_samples)
- Recalculates time vector and trigger information
- Downsampling factor must be a power of 2

# See also
- `downsample_edf`: Non-mutating version
- `crop_edf`: Reduce data length
- `merge_edf`: Combine multiple files
"""
function downsample_edf!(edf::EdfData, dec::Int)

  !ispow2(dec) && error("dec should be power of 2!")
  @info "Downsampling data by factor: $dec"

  # padding at start/end
  nsamp = min(dec * 20, size(edf.data, 1))  # enough samples, bounded by actual length
  ndec = div(nsamp, dec)

  data = Matrix{Float32}(undef, div(size(edf.data, 1), dec), size(edf.data, 2))
  for i in 1:size(edf.data, 2)
    start_pad = reverse(edf.data[1:nsamp, i])
    end_pad = reverse(edf.data[end-(nsamp-1):end, i])
    padded_data = vcat(start_pad, edf.data[:, i], end_pad)
    tmp_dat = resample(padded_data, 1 / dec)
    data[:, i] = convert(Vector{Float32}, tmp_dat[ndec+1:end-ndec])
  end
  edf.data = data

  edf.header.sample_rate = div.(edf.header.sample_rate, dec)
  edf.header.num_samples = div.(edf.header.num_samples, dec)
  edf.time = (0:size(edf.data, 1)-1) / edf.header.sample_rate[1]

  # update triggers
  edf.triggers.raw = zeros(Int16, size(edf.data, 1))
  edf.triggers.idx = convert(Vector{Int64}, round.(edf.triggers.idx / dec))
  valid_indices = filter(x -> 1 <= x <= size(edf.data, 1), edf.triggers.idx)
  if length(valid_indices) > 0
    edf.triggers.raw[valid_indices] = edf.triggers.val[1:length(valid_indices)]
  end

end


"""
    downsample_edf(edf_in, dec)

Reduce the sampling rate of EDF data by an integer factor (non-mutating).

# Arguments
- `edf_in::EdfData`: Input data structure
- `dec::Int`: Downsampling factor (must be power of 2)

# Returns
- `EdfData`: New downsampled data structure

# Examples
```julia
# Downsample and get new structure
dat_ds = downsample_edf(dat, 2)
dat_ds = downsample_edf(dat, 4)
```

# Notes
- Returns a new data structure (original unchanged)
- Calls `downsample_edf!` internally
- Useful when you want to preserve the original data

# See also
- `downsample_edf!`: In-place version
- `crop_edf`: Reduce data length
"""
function downsample_edf(edf_in::EdfData, dec::Int)
  edf_out = deepcopy(edf_in)
  downsample_edf!(edf_out, dec)
  return edf_out
end


"""
    merge_edf(edfs)

Merge multiple EDF data structures into a single file.

# Arguments
- `edfs::Array{EdfData}`: Array of EDF data structures to merge

# Returns
- `EdfData`: Merged data structure

# Requirements
- All files must have the same number of channels
- All files must have identical channel labels
- All files must have the same sampling rate

# Examples
```julia
# Merge two EDF files
file1 = "session1.edf"
file2 = "session2.edf"

dat1 = read_edf(file1)
dat2 = read_edf(file2)

dat_merged = merge_edf([dat1, dat2])

# Merge multiple files
files = ["session1.edf", "session2.edf", "session3.edf"]
data_arrays = [read_edf(f) for f in files]
dat_merged = merge_edf(data_arrays)
```

# Notes
- Files are concatenated in the order provided
- Header information is taken from the first file
- Trigger information is recalculated for the merged data
- Time vector is updated to reflect the total duration
- Original files are not modified

# See also
- `read_edf`: Read individual EDF files
- `crop_edf`: Reduce data length
- `select_channels_edf`: Select specific channels
"""
function merge_edf(edfs::Array{EdfData})

  file_names = join([x.filename for x in edfs], ", ")
  @info "Merging files: $file_names"

  # check data structs to merge have same number of channels, channel labels + sample rate
  num_chans = (x -> x.header.num_channels).(edfs)
  !all(x -> x == num_chans[1], num_chans) && error("1+ files have different number of channels!")
  chan_labels = (x -> x.header.channel_labels).(edfs)
  !all(y -> y == chan_labels[1], chan_labels) && error("1+ files have different channel labels!")
  sample_rate = (x -> x.header.sample_rate).(edfs)
  !all(y -> y == sample_rate[1], sample_rate) && error("1+ files have different sample rates!")

  # make copy so that edf_in is not altered
  edf_out = deepcopy(edfs[1])

  # merge data
  edf_out.header.num_data_records = sum((x -> x.header.num_data_records).(edfs))
  edf_out.data = vcat((x -> x.data).(edfs)...)
  edf_out.status = vcat((x -> x.status).(edfs)...)

  # recaculate trigger information
  trig = vcat((x -> x.triggers.raw).(edfs)...)
  edf_out.triggers = trigger_info(trig, edf_out.header.sample_rate[1])

  # merged time 
  edf_out.time = time_range(edf_out.header.sample_rate[1], edf_out.header.num_data_records)

  return edf_out

end


"""
    recode_triggers!(edf; remove_triggers=[], recode_triggers=Dict{Int,Int}(), add_triggers=Dict{Int,Int}())

Recode, remove, and/or add trigger values in EDF data (in-place).

# Arguments
- `edf::EdfData`: Data structure to modify
- `remove_triggers::Vector{Int}`: Trigger values to remove (set to 0)
- `recode_triggers::Dict{Int,Int}`: Dictionary mapping old trigger values to new values
- `add_triggers::Dict{Int,Int}`: Dictionary mapping trigger values to sample indices where they should be added

# Returns
- `Nothing`: Modifies `edf` in-place

# Examples
```julia
# Recode trigger 1 to 2 and trigger 2 to 1
recode_triggers!(dat, recode_triggers=Dict(1 => 2, 2 => 1))

# Remove triggers 3 and 4
recode_triggers!(dat, remove_triggers=[3, 4])

# Add trigger 10 at sample index 1000
recode_triggers!(dat, add_triggers=Dict(10 => 1000))

# All operations: recode, remove, and add
recode_triggers!(dat, remove_triggers=[5], recode_triggers=Dict(1 => 10, 2 => 20), add_triggers=Dict(100 => 5000))
```

# Notes
- Modifies the original data structure
- Operations are applied in order: recode, remove, then add
- Removed triggers are set to 0 in the raw trigger channel
- Added triggers are set at the specified sample indices
- Sample indices must be within the valid range [1, length(data)]
- Trigger information (idx, val, count, time) is recalculated after all modifications
- Use `recode_triggers` for non-mutating version

# See also
- `recode_triggers`: Non-mutating version
- `crop_edf!`: Crop data between triggers
"""
function recode_triggers!(edf::EdfData; remove_triggers::Vector{Int}=Int[], recode_triggers::Dict{Int,Int}=Dict{Int,Int}(), add_triggers::Dict{Int,Int}=Dict{Int,Int}())

  @info "Recoding triggers: remove=$remove_triggers, recode=$recode_triggers, add=$add_triggers"

  # Keep original unchanged, work from original to new
  trig_original = edf.triggers.raw
  trig_new = copy(trig_original)
  data_length = length(trig_new)

  # Apply recoding - always read from original, write to new
  for (old_val, new_val) in recode_triggers
    trig_new[trig_original.==old_val] .= new_val
  end

  # Remove specified triggers (set to 0) - read from original to avoid conflicts
  for val in remove_triggers
    trig_new[trig_original.==val] .= 0
  end

  # Add new triggers at specified sample indices
  for (trigger_val, sample_idx) in add_triggers
    if 1 <= sample_idx <= data_length
      trig_new[sample_idx] = trigger_val
    else
      @warn "Sample index $sample_idx out of range [1, $data_length], skipping trigger $trigger_val"
    end
  end

  # Recalculate trigger information
  edf.triggers = trigger_info(trig_new, edf.header.sample_rate[1])

end


"""
    recode_triggers(edf_in; remove_triggers=[], recode_triggers=Dict{Int,Int}(), add_triggers=Dict{Int,Int}())

Recode, remove, and/or add trigger values in EDF data (non-mutating).

# Arguments
- `edf_in::EdfData`: Input data structure
- `remove_triggers::Vector{Int}`: Trigger values to remove (set to 0)
- `recode_triggers::Dict{Int,Int}`: Dictionary mapping old trigger values to new values
- `add_triggers::Dict{Int,Int}`: Dictionary mapping trigger values to sample indices where they should be added

# Returns
- `EdfData`: New data structure with recoded triggers

# Examples
```julia
# Recode trigger 1 to 2 and trigger 2 to 1
dat_recoded = recode_triggers(dat, recode_triggers=Dict(1 => 2, 2 => 1))

# Remove triggers 3 and 4
dat_cleaned = recode_triggers(dat, remove_triggers=[3, 4])

# Add trigger 10 at sample index 1000
dat_with_new = recode_triggers(dat, add_triggers=Dict(10 => 1000))

# All operations: recode, remove, and add
dat_modified = recode_triggers(dat, remove_triggers=[5], recode_triggers=Dict(1 => 10, 2 => 20), add_triggers=Dict(100 => 5000))
```

# Notes
- Returns a new data structure (original unchanged)
- Calls `recode_triggers!` internally
- Useful when you want to preserve the original data

# See also
- `recode_triggers!`: In-place version
- `crop_edf`: Crop data between triggers
"""
function recode_triggers(edf_in::EdfData; remove_triggers::Vector{Int}=Int[], recode_triggers::Dict{Int,Int}=Dict{Int,Int}(), add_triggers::Dict{Int,Int}=Dict{Int,Int}())
  edf_out = deepcopy(edf_in)
  recode_triggers!(edf_out, remove_triggers=remove_triggers, recode_triggers=recode_triggers, add_triggers=add_triggers)
  return edf_out
end


"""
    time_range(sample_rate, num_data_records)

Generate time vector for EDF data.

# Arguments
- `sample_rate::Int`: Sampling rate in Hz
- `num_data_records::Int`: Number of data records

# Returns
- `StepRangeLen{Float64}`: Time vector starting at 0

# Time Calculation
- Time starts at 0 seconds
- Increments by 1/sample_rate for each sample
- Ends at (num_data_records - 1/sample_rate) seconds
- Total duration = num_data_records seconds

# Examples
```julia
# 60 seconds of data at 256 Hz
time = time_range(256, 60)
@assert length(time) == 256 * 60
@assert first(time) == 0.0
@assert last(time) == 59.99609375  # (60 - 1/256)
```

# Notes
- This is an internal function used by other functions
- Time vector length matches the number of data samples
- Useful for plotting and time-based operations
"""
function time_range(sample_rate::Int, num_data_records::Int)
  return 0:1/sample_rate:(num_data_records-(1/sample_rate))
end


"""
    trigger_info(trig_raw, sample_rate)

Extract trigger event information from raw trigger channel data.

# Arguments
- `trig_raw::Vector{Int16}`: Raw trigger values for each sample
- `sample_rate::Int`: Sampling rate in Hz

# Returns
- `EdfTriggers`: Structured trigger information containing:
  - `raw`: Original trigger values
  - `idx`: Sample indices where triggers occur
  - `val`: Trigger values at trigger events
  - `count`: Count of each trigger value
  - `time`: Trigger timing matrix [value, time_since_previous]

# Algorithm
1. Finds sample indices where trigger values change (diff ≥ 1)
2. Extracts trigger values at those indices
3. Calculates time intervals between consecutive triggers
4. Counts occurrences of each trigger value
5. Creates timing matrix with trigger values and intervals

# Notes
- This is an internal function used by `read_edf`
- Trigger events are detected when the trigger value increases
- Time intervals are calculated in seconds
- The first trigger has time interval 0
"""
function trigger_info(trig_raw, sample_rate)

  trig_idx = Int[]
  trig_val = Int[]

  # Find trigger rising edges sequentially 
  @inbounds for i in eachindex(trig_raw)
    i == firstindex(trig_raw) && continue
    if trig_raw[i] - trig_raw[i-1] >= 1
      push!(trig_idx, i)
      push!(trig_val, trig_raw[i])
    end
  end

  # Create trigger timing matrix
  trig_time = Matrix{Float64}(undef, length(trig_idx), 2)
  if !isempty(trig_idx)
    trig_time[1, 1] = trig_val[1]
    trig_time[1, 2] = 0.0
    @inbounds for i in eachindex(trig_idx)
      i == firstindex(trig_idx) && continue
      trig_time[i, 1] = trig_val[i]
      trig_time[i, 2] = (trig_idx[i] - trig_idx[i-1]) / sample_rate
    end
  end

  # Count unique triggers
  trig_count = OrderedDict{Int,Int}()
  for val in sort!(collect(Set(trig_val)))
    trig_count[val] = 0
  end
  for val in trig_val
    trig_count[val] += 1
  end

  return EdfTriggers(trig_raw, trig_idx, trig_val, trig_count, trig_time)

end


# Internal helper functions for cropping
function crop_check(crop_type::String, val::Array{Int}, triggers, num_data_records)
  crop_type ∉ ["triggers", "records"] && error("crop_type not recognized!")
  length(val) != 2 && error("val should be of length 2!")
  if crop_type == "triggers"
    val[1] ∉ triggers && error("val[1] not available trigger!")
    val[2] ∉ triggers && error("val[2] not available trigger!")
  elseif crop_type == "records"
    val[1] < 1 && error("val[1] less than 1")
    val[2] > num_data_records && error("val[2] > number of data records!")
  end
end

function find_crop_index(triggers::EdfTriggers, crop_type::String, val::Array{Int}, sample_rate::Int, data_length::Int)
  # find idxStart/idxEnd 
  if crop_type == "triggers"
    borders = 1:sample_rate:data_length
    trigStart = findfirst(triggers.val .== val[1])
    trigEnd = findlast(triggers.val .== val[2])
    idxStart = triggers.idx[trigStart]
    idxStart = findfirst(borders .>= idxStart) * sample_rate
    idxEnd = triggers.idx[trigEnd]
    idxEnd = (findlast(borders .<= idxEnd) * sample_rate) - 1
  elseif crop_type == "records"
    idxStart = ((val[1] - 1) * sample_rate) + 1
    idxEnd = (val[2] * sample_rate)
  end
  return idxStart, idxEnd
end
