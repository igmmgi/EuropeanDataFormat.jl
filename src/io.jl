# io.jl - Input/Output functions for EuropeanDataFormat

"""
    read_edf(filename; header_only=false, channels=[])

Read EDF Data Format (EDF) files into Julia data structures.

# Arguments
- `filename::String`: Path to the EDF file
- `header_only::Bool=false`: If `true`, only read header information and return `EdfHeader`
- `channels::Vector{<:Union{Int,String}}=[]`: Specific channels to read
  - Empty vector (default): read all channels
  - Vector of integers: channel indices (1-based, excluding status channel)
  - Vector of strings: channel labels (e.g., ["Fp1", "Cz"])
  - Use `-1` to include only the trigger/status channel
  - Mix of types allowed (e.g., [1, "Fp1", -1])

# Returns
- `EdfData`: Complete data structure with header, data, time, triggers, and status
- `EdfHeader`: If `header_only=true`

# Data Structure
The returned `EdfData` contains:
- `header`: File metadata and channel information
- `data`: EEG data matrix (samples × selected_channels)
- `time`: Time vector starting at 0
- `triggers`: Trigger event information
- `status`: Status channel values

# Examples
```julia
# Read entire file
dat = read_edf("data.edf")

# Read only header
hdr = read_edf("data.edf", header_only=true)

# Read specific channels by index
dat = read_edf("data.edf", channels=[1, 3, 5])

# Read specific channels by label
dat = read_edf("data.edf", channels=["Fp1", "Cz", "A1"])

# Read only trigger channel
dat = read_edf("data.edf", channels=[-1])

# Mix of channel types
dat = read_edf("data.edf", channels=[1, "Fp1", -1])
```

# Notes
- Channel indices are 1-based
- The status/trigger channel is always included automatically
- Data is automatically scaled using header calibration information
- Trigger information is extracted from the status channel
- File format follows [EDF EDF specification](https://www.edf.com/faq_file_format.htm)
- The EDF/EDF+ specification allows different channels to have different sampling rates. When reading files with mixed sampling rates, the package automatically upsamples slower channels to match the highest sampling rate in the file.
- EDF Annotations channels (EDF+) are automatically detected and excluded from data/triggers.
  Trigger extraction uses the "Status" channel when present.

# See also
- `write_edf`: Write data back to EDF format
- `crop_edf`: Reduce data length
- `select_channels_edf`: Select channels after reading
"""
function read_edf(filename::AbstractString; header_only::Bool=false, channels=[])

  @info "Reading file: $filename"
  if !isfile(filename)
    error("File $filename does not exist!")
  end
  fid = open(filename, "r")

  # create header dictionary
  id1 = read!(fid, Array{UInt8}(undef, 1))
  id2 = read!(fid, Array{UInt8}(undef, EDF_ID_BYTES - 1))
  text1 = String(read!(fid, Array{UInt8}(undef, EDF_TEXT_BYTES)))
  text2 = String(read!(fid, Array{UInt8}(undef, EDF_TEXT_BYTES)))
  start_date = String(read!(fid, Array{UInt8}(undef, EDF_DATE_BYTES)))
  start_time = String(read!(fid, Array{UInt8}(undef, EDF_TIME_BYTES)))
  num_bytes_header = parse(Int, String(read!(fid, Array{UInt8}(undef, EDF_HEADER_SIZE_BYTES))))
  data_format = strip(String(read!(fid, Array{UInt8}(undef, EDF_DATA_FORMAT_BYTES))))
  num_data_records = parse(Int, String(read!(fid, Array{UInt8}(undef, EDF_RECORD_COUNT_BYTES))))
  duration_data_records = parse(Float64, String(read!(fid, Array{UInt8}(undef, EDF_DURATION_BYTES))))
  num_channels_file = parse(Int, String(read!(fid, Array{UInt8}(undef, EDF_CHANNEL_COUNT_BYTES))))
  channel_labels = [strip(String(read!(fid, Array{UInt8}(undef, EDF_CHANNEL_LABEL_BYTES)))) for _ in 1:num_channels_file]
  transducer_type = [strip(String(read!(fid, Array{UInt8}(undef, EDF_TRANSDUCER_BYTES)))) for _ in 1:num_channels_file]
  channel_unit = [strip(String(read!(fid, Array{UInt8}(undef, EDF_UNIT_BYTES)))) for _ in 1:num_channels_file]
  physical_min = parse.(Float32, [String(read!(fid, Array{UInt8}(undef, EDF_VALUE_BYTES))) for _ in 1:num_channels_file])
  physical_max = parse.(Float32, [String(read!(fid, Array{UInt8}(undef, EDF_VALUE_BYTES))) for _ in 1:num_channels_file])
  digital_min = parse.(Float32, [String(read!(fid, Array{UInt8}(undef, EDF_VALUE_BYTES))) for _ in 1:num_channels_file])
  digital_max = parse.(Float32, [String(read!(fid, Array{UInt8}(undef, EDF_VALUE_BYTES))) for _ in 1:num_channels_file])
  pre_filter = [strip(String(read!(fid, Array{UInt8}(undef, EDF_FILTER_BYTES)))) for _ in 1:num_channels_file]
  num_samples = parse.(Int, [String(read!(fid, Array{UInt8}(undef, EDF_SAMPLES_BYTES))) for _ in 1:num_channels_file])
  reserved = [String(read!(fid, Array{UInt8}(undef, EDF_RESERVED_BYTES))) for _ in 1:num_channels_file]

  # Detect EDF Annotations channel(s) and Status channel
  annotations_idx = findall(x -> x == "EDF Annotations", channel_labels)
  status_idx = findlast(x -> x == "Status", channel_labels)

  # Determine which channels are "real" data channels (excluding annotations)
  # and which channel serves as the trigger/status source
  if !isempty(annotations_idx)
    # EDF+ file: annotations channels are not data channels
    # Keep all non-annotation channels for data
    keep_indices = setdiff(1:num_channels_file, annotations_idx)
  else
    keep_indices = 1:num_channels_file
  end

  # Determine the trigger source channel (in the original file indexing)
  # Only use an explicit "Status" channel — never assume the last channel is status
  if status_idx !== nothing && status_idx ∉ annotations_idx
    trigger_source_idx = status_idx
  else
    trigger_source_idx = 0
  end

  # Build header with only the kept channels
  num_channels = length(keep_indices)
  kl = keep_indices  # shorthand
  channel_labels_kept = channel_labels[kl]
  transducer_type_kept = transducer_type[kl]
  channel_unit_kept = channel_unit[kl]
  physical_min_kept = physical_min[kl]
  physical_max_kept = physical_max[kl]
  digital_min_kept = digital_min[kl]
  digital_max_kept = digital_max[kl]
  pre_filter_kept = pre_filter[kl]
  num_samples_kept = num_samples[kl]
  reserved_kept = reserved[kl]

  scale_factor = convert(Array{Float32}, ((physical_max_kept .- physical_min_kept) ./ (digital_max_kept .- digital_min_kept)))
  offset = convert(Array{Float32}, physical_max_kept .- scale_factor .* digital_max_kept)
  sample_rate = convert(Array{Int}, round.(Int, num_samples_kept ./ duration_data_records))

  hd = EdfHeader(id1, id2, text1, text2, start_date, start_time, num_bytes_header, data_format,
    num_data_records, duration_data_records, num_channels, channel_labels_kept, transducer_type_kept,
    channel_unit_kept, physical_min_kept, physical_max_kept, digital_min_kept, digital_max_kept, pre_filter_kept,
    num_samples_kept, reserved_kept, scale_factor, offset, sample_rate)

  if header_only
    close(fid)
    return hd
  end

  # read data — must read ALL channels from file (including annotations) to maintain byte offsets
  edf_uint8 = read!(fid, Array{UInt8}(undef, EDF_SAMPLES_PER_BYTE * num_data_records * sum(num_samples)))
  close(fid)
  edf = reinterpret(Int16, edf_uint8)

  # Find the trigger source index within the kept channels
  trigger_kept_idx = trigger_source_idx > 0 ? findfirst(==(trigger_source_idx), collect(keep_indices)) : 0

  # Map user-requested channels from kept indices to file indices
  if !isempty(channels)
    user_channels = channel_index(channel_labels_kept, channels, trigger_kept_idx)
  else
    user_channels = 1:num_channels
  end

  dat, time, trig, status = edf2matrix(edf, keep_indices, user_channels,
    scale_factor, offset, num_data_records, num_samples, sample_rate[1], trigger_kept_idx)
  user_channels != 1:num_channels && update_header_edf!(hd, collect(user_channels))

  triggers = trigger_info(trig, sample_rate[1])

  return EdfData(filename, hd, dat, time, triggers, status)

end


"""
    write_edf(edf_in, filename="")

Write EDF data structure to an EDF file.

# Arguments
- `edf_in::EdfData`: Data structure to write
- `filename::String=""`: Output filename (uses original filename if empty)

# Returns
- `Nothing`: Writes file to disk

# Examples
```julia
# Write to a new file
write_edf(dat, "processed_data.edf")

# Write using original filename
dat.filename = "my_data.edf"
write_edf(dat)

# Write processed data
dat_cropped = crop_edf(dat, "triggers", [100, 200])
write_edf(dat_cropped, "cropped_data.edf")
```

# Notes
- Creates a new EDF file in standard 16-bit EDF format
- Automatically applies scale factors and converts to 16-bit format
- Preserves all header information and metadata
- If no filename is provided, uses the filename stored in the data structure
- Overwrites existing files without warning

# See also
- `read_edf`: Read EDF files
- `crop_edf`: Reduce data before writing
- `select_channels_edf`: Select channels before writing
"""
function write_edf(edf_in::EdfData, filename::AbstractString="")

  if isempty(filename)
    filename = edf_in.filename
  end
  fid = open(filename, "w")

  _write_bytes(fid, edf_in.header.id1)
  _write_bytes(fid, edf_in.header.id2)
  _write_bytes(fid, edf_in.header.text1)
  _write_bytes(fid, edf_in.header.text2)
  _write_bytes(fid, edf_in.header.start_date)
  _write_bytes(fid, edf_in.header.start_time)
  _write_bytes(fid, rpad(string(edf_in.header.num_bytes_header), EDF_HEADER_SIZE_BYTES))
  _write_bytes(fid, rpad(edf_in.header.data_format, EDF_DATA_FORMAT_BYTES))
  _write_bytes(fid, rpad(string(edf_in.header.num_data_records), EDF_RECORD_COUNT_BYTES))
  _write_bytes(fid, rpad(string(edf_in.header.duration_data_records), EDF_DURATION_BYTES))
  _write_bytes(fid, rpad(string(edf_in.header.num_channels), EDF_CHANNEL_COUNT_BYTES))
  _write_padded(fid, edf_in.header.channel_labels, EDF_CHANNEL_LABEL_BYTES)
  _write_padded(fid, edf_in.header.transducer_type, EDF_TRANSDUCER_BYTES)
  _write_padded(fid, edf_in.header.channel_unit, EDF_UNIT_BYTES)
  _write_padded(fid, edf_in.header.physical_min, EDF_VALUE_BYTES)
  _write_padded(fid, edf_in.header.physical_max, EDF_VALUE_BYTES)
  _write_padded(fid, edf_in.header.digital_min, EDF_VALUE_BYTES)
  _write_padded(fid, edf_in.header.digital_max, EDF_VALUE_BYTES)
  _write_padded(fid, edf_in.header.pre_filter, EDF_FILTER_BYTES)
  _write_padded(fid, edf_in.header.num_samples, EDF_SAMPLES_BYTES)
  _write_padded(fid, edf_in.header.reserved, EDF_RESERVED_BYTES)

  # Determine which header channels are data channels (not Status)
  status_idx = _find_status_index(edf_in.header.channel_labels)
  if status_idx > 0
    data_chan_indices = filter(!=(status_idx), 1:edf_in.header.num_channels)
  else
    data_chan_indices = 1:edf_in.header.num_channels
  end

  data = round.(Int32, ((edf_in.data .- transpose(edf_in.header.offset[data_chan_indices])) ./ transpose(edf_in.header.scale_factor[data_chan_indices])))
  trigs = edf_in.triggers.raw
  num_data_records = edf_in.header.num_data_records
  num_samples = edf_in.header.num_samples
  num_channels = edf_in.header.num_channels

  edf = matrix2edf(data, trigs, num_data_records, num_samples, num_channels, status_idx)

  @info "Writing file: $filename"
  write(fid, reinterpret(UInt8, edf))
  close(fid)

end


# Internal helpers for zero-allocation byte writing
function _write_bytes(fid::IO, data)
  for b in data
    write(fid, UInt8(b))
  end
end

function _write_padded(fid::IO, values, pad_length)
  for val in values
    _write_bytes(fid, rpad(val, pad_length))
  end
end


"""
    edf2matrix(edf, keep_indices, user_channels, scale_factor, offset, num_data_records, num_samples, sample_rate, trigger_kept_idx)

Convert raw EDF binary data to Julia data matrix and extract trigger information.

# Arguments
- `edf::AbstractVector{Int16}`: Raw 16-bit binary EDF data
- `keep_indices::Union{Vector{Int},UnitRange{Int}}`: Indices of non-annotation channels in the file
- `user_channels::Union{Vector{Int},UnitRange{Int}}`: User-selected channel indices within keep_indices
- `scale_factor::Vector{Float32}`: Scale factors for each kept channel
- `offset::Vector{Float32}`: Offsets for each kept channel
- `num_data_records::Int`: Number of data records
- `num_samples::Vector{Int}`: Number of samples per record per file channel
- `sample_rate::Int`: Sampling rate in Hz
- `trigger_kept_idx::Int`: Index of trigger channel within keep_indices (0 = no trigger channel)

# Returns
- `dat_chans::Matrix{Float32}`: Scaled EEG data matrix (samples × channels)
- `time::StepRangeLen{Float64}`: Time vector for each sample
- `trig_chan::Vector{Int16}`: Raw trigger values for each sample
- `status_chan::Vector{Int16}`: Status channel values for each sample

# Notes
- Converts 16-bit EDF format to 32-bit float data
- Automatically applies scale factors for physical units
- Extracts trigger and status information from the designated status channel
- Time vector starts at 0 and increments by 1/sample_rate
- This is an internal function used by `read_edf`
"""
function edf2matrix(edf::AbstractVector{Int16}, keep_indices, user_channels,
    scale_factor, offset_factor, num_data_records, num_samples::Vector{Int},
    sample_rate, trigger_kept_idx::Int)

  target_samples = num_samples[collect(keep_indices)[1]]
  total_samples = num_data_records * target_samples

  # Count data channels (non-trigger channels that user requested)
  user_set = Set(user_channels)
  n_data_chans = trigger_kept_idx > 0 ? count(c -> c != trigger_kept_idx && c in user_set, 1:length(keep_indices)) :
                                         count(c -> c in user_set, 1:length(keep_indices))

  dat_chans = Matrix{Float32}(undef, total_samples, n_data_chans)
  time = time_range(sample_rate, num_data_records)
  
  if trigger_kept_idx > 0
    trig_chan = Vector{Int16}(undef, total_samples)
  else
    trig_chan = zeros(Int16, total_samples)
  end
  status_chan = zeros(Int16, total_samples)

  # Precompute channel Int16 offsets within a record (using FILE channel indices)
  chan_offsets = cumsum([0; num_samples[1:end-1]])
  samples_per_record = sum(num_samples)

  # Build mapping: for each kept channel, what is its file index and kept index?
  keep_vec = collect(keep_indices)

  for rec = 0:(num_data_records-1)
    rec_offset = rec * samples_per_record
    data_offset = rec * target_samples
    dat_col = 0

    for (kept_idx, file_chan) in enumerate(keep_vec)
      kept_idx in user_set || continue

      n_samp = num_samples[file_chan]
      pos = 1 + rec_offset + chan_offsets[file_chan]

      if kept_idx == trigger_kept_idx
        # This is the trigger/status channel
        last_trig = Int16(0)
        @inbounds for samp = 1:min(n_samp, target_samples)
          last_trig = ltoh(edf[pos])
          trig_chan[data_offset+samp] = last_trig
          pos += 1
        end
        @inbounds for samp = n_samp+1:target_samples
          trig_chan[data_offset+samp] = last_trig
        end
      else
        # Data channel
        dat_col += 1
        sf = scale_factor[kept_idx]
        of = offset_factor[kept_idx]
        last_val = 0.0f0
        @inbounds for samp = 1:min(n_samp, target_samples)
          last_val = Float32(ltoh(edf[pos])) * sf + of
          dat_chans[data_offset+samp, dat_col] = last_val
          pos += 1
        end
        @inbounds for samp = n_samp+1:target_samples
          dat_chans[data_offset+samp, dat_col] = last_val
        end
      end
    end
  end

  return dat_chans, time, trig_chan, status_chan

end


"""
    matrix2edf(data, trigs, status, num_data_records, num_samples, num_channels)

Convert Julia data matrix back to EDF 16-bit binary format.

# Arguments
- `data::Matrix{<:Number}`: EEG data matrix (samples × channels)
- `trigs::Vector{<:Integer}`: Trigger values for each sample
- `status::Vector{<:Integer}`: Status channel values for each sample
- `num_data_records::Int`: Number of data records
- `num_samples::Int`: Number of samples per record per channel
- `num_channels::Int`: Total number of channels (including status)

# Returns
- `Vector{UInt8}`: Binary data in EDF 16-bit format

# Format
- Each sample is stored as 2 bytes (16-bit)
- Data is written in record-major order (record × channel × sample)
- Status channel is written last for each record
- This is an internal function used by `write_edf`

# Notes
- Converts float data back to integer format
- Applies inverse scaling to restore original digital values
- Maintains EDF file structure and byte ordering
"""
function matrix2edf(data, trigs, num_data_records, num_samples::Vector{Int}, num_channels, status_idx::Int=0)
  edf = Array{Int16}(undef, num_data_records * sum(num_samples))
  target_samples = num_samples[1]
  samples_per_record = sum(num_samples)
  chan_offsets = cumsum([0; num_samples[1:end-1]])

  for rec = 0:(num_data_records-1)
    rec_offset = rec * samples_per_record
    offset = rec * target_samples
    data_col = 0

    for chan = 1:num_channels
      n_samp = num_samples[chan]
      pos = 1 + rec_offset + chan_offsets[chan]

      if chan == status_idx
        # Status/trigger channel
        @inbounds for samp = 1:min(n_samp, target_samples)
          trig_val = trigs[offset+samp]
          edf[pos] = htol(Int16(trig_val))
          pos += 1
        end
        @inbounds for _ in target_samples+1:n_samp
          edf[pos] = 0x0000
          pos += 1
        end
      else
        # Data channel
        data_col += 1
        @inbounds for samp = 1:min(n_samp, target_samples)
          data_val = data[offset+samp, data_col]
          edf[pos] = htol(Int16(data_val))
          pos += 1
        end
        @inbounds for _ in target_samples+1:n_samp
          edf[pos] = 0x0000
          pos += 1
        end
      end
    end
  end
  return edf
end


"""
    update_header_edf!(hd, channels)

Update header information after channel selection/deletion.

# Arguments
- `hd::EdfHeader`: Header to modify
- `channels::Vector{Int}`: Selected channel indices (including status channel)

# Returns
- `Nothing`: Modifies `hd` in-place

# Updated Fields
- `num_channels`: Number of selected channels
- `channel_labels`: Labels of selected channels
- `transducer_type`: Transducer types for selected channels
- `channel_unit`: Units for selected channels
- `physical_min`: Physical minimum values for selected channels
- `physical_max`: Physical maximum values for selected channels
- `digital_min`: Digital minimum values for selected channels
- `digital_max`: Digital maximum values for selected channels
- `pre_filter`: Pre-filtering information for selected channels
- `num_samples`: Number of samples for selected channels
- `reserved`: Reserved header space for selected channels
- `scale_factor`: Scale factors for selected channels
- `sample_rate`: Sampling rates for selected channels
- `num_bytes_header`: Updated header size

# Notes
- This is an internal function used by channel manipulation functions
- Automatically recalculates `num_bytes_header` based on channel count
- Preserves the status channel as the last channel
- Updates all channel-specific header fields
"""
function update_header_edf!(hd::EdfHeader, channels::Array{Int})

  hd.num_channels = length(channels)
  hd.channel_labels = hd.channel_labels[channels]
  hd.transducer_type = hd.transducer_type[channels]
  hd.channel_unit = hd.channel_unit[channels]
  hd.physical_min = hd.physical_min[channels]
  hd.physical_max = hd.physical_max[channels]
  hd.digital_min = hd.digital_min[channels]
  hd.digital_max = hd.digital_max[channels]
  hd.pre_filter = hd.pre_filter[channels]
  hd.num_samples = hd.num_samples[channels]
  hd.reserved = hd.reserved[channels]
  hd.scale_factor = hd.scale_factor[channels]
  hd.offset = hd.offset[channels]
  hd.sample_rate = hd.sample_rate[channels]
  hd.num_bytes_header = (length(channels) + EDF_STATUS_CHANNEL_OFFSET) * EDF_HEADER_SIZE

end
