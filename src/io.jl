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

# See also
- `write_edf`: Write data back to EDF format
- `crop_edf`: Reduce data length
- `select_channels_edf`: Select channels after reading
"""
function read_edf(filename::String; header_only::Bool=false, channels=[])

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
  duration_data_records = parse(Int, String(read!(fid, Array{UInt8}(undef, EDF_DURATION_BYTES))))
  num_channels = parse(Int, String(read!(fid, Array{UInt8}(undef, EDF_CHANNEL_COUNT_BYTES))))
  channel_labels = [strip(String(read!(fid, Array{UInt8}(undef, EDF_CHANNEL_LABEL_BYTES)))) for _ in 1:num_channels]
  transducer_type = [strip(String(read!(fid, Array{UInt8}(undef, EDF_TRANSDUCER_BYTES)))) for _ in 1:num_channels]
  channel_unit = [strip(String(read!(fid, Array{UInt8}(undef, EDF_UNIT_BYTES)))) for _ in 1:num_channels]
  physical_min = parse.(Float32, [String(read!(fid, Array{UInt8}(undef, EDF_VALUE_BYTES))) for _ in 1:num_channels])
  physical_max = parse.(Float32, [String(read!(fid, Array{UInt8}(undef, EDF_VALUE_BYTES))) for _ in 1:num_channels])
  digital_min = parse.(Float32, [String(read!(fid, Array{UInt8}(undef, EDF_VALUE_BYTES))) for _ in 1:num_channels])
  digital_max = parse.(Float32, [String(read!(fid, Array{UInt8}(undef, EDF_VALUE_BYTES))) for _ in 1:num_channels])
  pre_filter = [strip(String(read!(fid, Array{UInt8}(undef, EDF_FILTER_BYTES)))) for _ in 1:num_channels]
  num_samples = parse.(Int, [String(read!(fid, Array{UInt8}(undef, EDF_SAMPLES_BYTES))) for _ in 1:num_channels])
  reserved = [String(read!(fid, Array{UInt8}(undef, EDF_RESERVED_BYTES))) for _ in 1:num_channels]
  scale_factor = convert(Array{Float32}, ((physical_max .- physical_min) ./ (digital_max .- digital_min)))
  offset = convert(Array{Float32}, physical_max .- scale_factor .* digital_max)
  sample_rate = convert(Array{Int}, num_samples ./ duration_data_records)

  hd = EdfHeader(id1, id2, text1, text2, start_date, start_time, num_bytes_header, data_format,
    num_data_records, duration_data_records, num_channels, channel_labels, transducer_type,
    channel_unit, physical_min, physical_max, digital_min, digital_max, pre_filter,
    num_samples, reserved, scale_factor, offset, sample_rate)

  if header_only
    close(fid)
    return hd
  end

  # read data
  edf = read!(fid, Array{UInt8}(undef, EDF_SAMPLES_PER_BYTE * num_data_records * sum(num_samples)))
  close(fid)

  channels = !isempty(channels) ? channel_index(channel_labels, channels) : 1:num_channels

  dat, time, trig, status = edf2matrix(edf, num_channels, channels, scale_factor, offset, num_data_records, num_samples, sample_rate[1])
  channels != 1:num_channels && update_header_edf!(hd, channels)

  triggers = trigger_info(trig, sample_rate[1])

  return EdfData(filename, hd, dat, time, triggers, status)

end


"""
    write_edf(edf_in, filename="")

Write EDF EDF data structure to a EDF file.

# Arguments
- `edf_in::EdfData`: Data structure to write
- `filename::String=""`: Output filename. If empty, uses `edf_in.filename`

# File Format
Writes data in EDF 16-bit format with:
- 256-byte header containing metadata
- 16-bit data samples for each channel
- Status channel as the last channel
- Proper scaling and calibration information

# Header Information
The header includes:
- File identification and metadata
- Channel information (labels, units, ranges)
- Sampling rate and data record information
- Pre-filtering and transducer information

# Examples
```julia
# Write to specified filename
write_edf(dat, "output.edf")

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
- Creates a new EDF file in standard EDF format
- Automatically applies scale factors and converts to 16-bit format
- Preserves all header information and metadata
- If no filename is provided, uses the filename stored in the data structure
- Overwrites existing files without warning

# See also
- `read_edf`: Read EDF files
- `crop_edf`: Reduce data before writing
- `select_channels_edf`: Select channels before writing
"""
function write_edf(edf_in::EdfData, filename::String="")

  if isempty(filename)
    filename = edf_in.filename
  end
  fid = open(filename, "w")

  [write(fid, UInt8(i)) for i in edf_in.header.id1]
  [write(fid, UInt8(i)) for i in edf_in.header.id2]
  [write(fid, UInt8(i)) for i in edf_in.header.text1]
  [write(fid, UInt8(i)) for i in edf_in.header.text2]
  [write(fid, UInt8(i)) for i in edf_in.header.start_date]
  [write(fid, UInt8(i)) for i in edf_in.header.start_time]
  [write(fid, UInt8(i)) for i in rpad(string(edf_in.header.num_bytes_header), EDF_HEADER_SIZE_BYTES)]
  [write(fid, UInt8(i)) for i in rpad(edf_in.header.data_format, EDF_DATA_FORMAT_BYTES)]
  [write(fid, UInt8(i)) for i in rpad(string(edf_in.header.num_data_records), EDF_RECORD_COUNT_BYTES)]
  [write(fid, UInt8(i)) for i in rpad(string(edf_in.header.duration_data_records), EDF_DURATION_BYTES)]
  [write(fid, UInt8(i)) for i in rpad(string(edf_in.header.num_channels), EDF_CHANNEL_COUNT_BYTES)]
  [write(fid, UInt8(j)) for i in edf_in.header.channel_labels for j in rpad(i, EDF_CHANNEL_LABEL_BYTES)]
  [write(fid, UInt8(j)) for i in edf_in.header.transducer_type for j in rpad(i, EDF_TRANSDUCER_BYTES)]
  [write(fid, UInt8(j)) for i in edf_in.header.channel_unit for j in rpad(i, EDF_UNIT_BYTES)]
  [write(fid, UInt8(j)) for i in edf_in.header.physical_min for j in rpad(i, EDF_VALUE_BYTES)]
  [write(fid, UInt8(j)) for i in edf_in.header.physical_max for j in rpad(i, EDF_VALUE_BYTES)]
  [write(fid, UInt8(j)) for i in edf_in.header.digital_min for j in rpad(i, EDF_VALUE_BYTES)]
  [write(fid, UInt8(j)) for i in edf_in.header.digital_max for j in rpad(i, EDF_VALUE_BYTES)]
  [write(fid, UInt8(j)) for i in edf_in.header.pre_filter for j in rpad(i, EDF_FILTER_BYTES)]
  [write(fid, UInt8(j)) for i in edf_in.header.num_samples for j in rpad(i, EDF_SAMPLES_BYTES)]
  [write(fid, UInt8(j)) for i in edf_in.header.reserved for j in rpad(i, EDF_RESERVED_BYTES)]

  data = round.(Int32, ((edf_in.data .- transpose(edf_in.header.offset[1:end-1])) ./ transpose(edf_in.header.scale_factor[1:end-1])))
  trigs = edf_in.triggers.raw
  num_data_records = edf_in.header.num_data_records
  num_samples = edf_in.header.num_samples
  num_channels = edf_in.header.num_channels

  edf = matrix2edf(data, trigs, num_data_records, num_samples, num_channels)

  @info "Writing file: $filename"
  write(fid, Array{UInt8}(edf))
  close(fid)

end


"""
    edf2matrix(edf, num_channels, channels, scale_factor, num_data_records, num_samples, sample_rate)

Convert raw EDF binary data to Julia data matrix and extract trigger information.

# Arguments
- `edf::Vector{UInt8}`: Raw binary data from EDF file
- `num_channels::Int`: Total number of channels in file
- `channels::Vector{Int}`: Selected channel indices (including status channel)
- `scale_factor::Vector{Float32}`: Scale factors for each channel
- `offset::Vector{Float32}`: Offsets for each channel
- `num_data_records::Int`: Number of data records
- `num_samples::Int`: Number of samples per record per channel
- `sample_rate::Int`: Sampling rate in Hz

# Returns
- `dat_chans::Matrix{Float32}`: Scaled EEG data matrix (samples × channels)
- `time::StepRangeLen{Float64}`: Time vector for each sample
- `trig_chan::Vector{Int16}`: Raw trigger values for each sample
- `status_chan::Vector{Int16}`: Status channel values for each sample

# Notes
- Converts 16-bit EDF format to 32-bit float data
- Automatically applies scale factors for physical units
- Extracts trigger and status information from the last channel
- Time vector starts at 0 and increments by 1/sample_rate
- This is an internal function used by `read_edf`
"""
function edf2matrix(edf, num_channels, channels, scale_factor, offset_factor, num_data_records, num_samples::Vector{Int}, sample_rate)

  target_samples = num_samples[1]
  dat_chans = Matrix{Float32}(undef, (num_data_records * target_samples), length(channels) - 1)
  time = time_range(sample_rate, num_data_records)
  trig_chan = Vector{Int16}(undef, num_data_records * target_samples)
  status_chan = zeros(Int16, num_data_records * target_samples)

  # Use Set for faster channel lookup
  # Use Set for faster channel lookup
  channels_set = Set(channels)

  # Precompute channel byte offsets within a record
  chan_byte_offsets = cumsum([0; num_samples[1:end-1]]) .* EDF_SAMPLES_PER_BYTE
  bytes_per_record = sum(num_samples) * EDF_SAMPLES_PER_BYTE

  for rec = 0:(num_data_records-1)
    rec_offset_bytes = rec * bytes_per_record
    offset = rec * target_samples
    chan_idx = 1
    
    for chan = 1:num_channels
      if chan in channels_set
        n_samp = num_samples[chan]
        pos = 1 + rec_offset_bytes + chan_byte_offsets[chan]
        
        if chan < num_channels
          sf = scale_factor[chan]
          of = offset_factor[chan]
          last_val = 0.0f0
          @simd for samp = 1:min(n_samp, target_samples)
            last_val = Float32(Int16(edf[pos]) | (Int16(edf[pos+1]) << 8)) * sf + of
            @inbounds dat_chans[offset+samp, chan_idx] = last_val
            pos += EDF_SAMPLES_PER_BYTE
          end
          for samp = n_samp+1:target_samples
            @inbounds dat_chans[offset+samp, chan_idx] = last_val
          end
        else  # last channel is always Status channel
          last_trig = Int16(0)
          @simd for samp = 1:min(n_samp, target_samples)
            last_trig = Int16(edf[pos]) | (Int16(edf[pos+1]) << 8)
            @inbounds trig_chan[offset+samp] = last_trig
            pos += EDF_SAMPLES_PER_BYTE
          end
          for samp = n_samp+1:target_samples
            @inbounds trig_chan[offset+samp] = last_trig
          end
        end
        chan_idx += 1
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
function matrix2edf(data, trigs, num_data_records, num_samples::Vector{Int}, num_channels)
  edf = Array{UInt8}(undef, EDF_SAMPLES_PER_BYTE * num_data_records * sum(num_samples))
  target_samples = num_samples[1]
  bytes_per_record = sum(num_samples) * EDF_SAMPLES_PER_BYTE
  chan_byte_offsets = cumsum([0; num_samples[1:end-1]]) .* EDF_SAMPLES_PER_BYTE

  for rec = 0:(num_data_records-1)
    rec_offset_bytes = rec * bytes_per_record
    offset = rec * target_samples

    for chan = 1:num_channels
      n_samp = num_samples[chan]
      pos = 1 + rec_offset_bytes + chan_byte_offsets[chan]

      if chan < num_channels
        @simd for samp = 1:min(n_samp, target_samples)
          data_val = data[offset+samp, chan]
          @inbounds edf[pos] = (data_val % UInt8)
          @inbounds edf[pos+1] = ((data_val >> 8) % UInt8)
          pos += EDF_SAMPLES_PER_BYTE
        end
        for _ in target_samples+1:n_samp
          @inbounds edf[pos] = 0x00
          @inbounds edf[pos+1] = 0x00
          pos += EDF_SAMPLES_PER_BYTE
        end
      else  # last channel is Status channel
        @simd for samp = 1:min(n_samp, target_samples)
          trig_val = trigs[offset+samp]
          @inbounds edf[pos] = trig_val % UInt8
          @inbounds edf[pos+1] = (trig_val >> 8) % UInt8
          pos += EDF_SAMPLES_PER_BYTE
        end
        for _ in target_samples+1:n_samp
          @inbounds edf[pos] = 0x00
          @inbounds edf[pos+1] = 0x00
          pos += EDF_SAMPLES_PER_BYTE
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
