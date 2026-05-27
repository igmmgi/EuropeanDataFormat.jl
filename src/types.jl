# types.jl - Type definitions and constants for EuropeanDataFormat

# EDF file format constants
const EDF_HEADER_SIZE = 256
const EDF_ID_BYTES = 8
const EDF_TEXT_BYTES = 80
const EDF_CHANNEL_LABEL_BYTES = 16
const EDF_TRANSDUCER_BYTES = 80
const EDF_UNIT_BYTES = 8
const EDF_VALUE_BYTES = 8
const EDF_FILTER_BYTES = 80
const EDF_SAMPLES_BYTES = 8
const EDF_RESERVED_BYTES = 32
const EDF_DATA_FORMAT_BYTES = 44
const EDF_DATE_BYTES = 8
const EDF_TIME_BYTES = 8
const EDF_CHANNEL_COUNT_BYTES = 4
const EDF_RECORD_COUNT_BYTES = 8
const EDF_DURATION_BYTES = 8
const EDF_HEADER_SIZE_BYTES = 8

# EDF data format constants
const EDF_SAMPLES_PER_BYTE = 2  # 16-bit samples stored as 2 bytes
const EDF_STATUS_CHANNEL_OFFSET = 1  # Status channel is always last

"""
    EdfHeader

Data structure containing EDF EDF file header information.

# Fields
- `id1::Vector{UInt8}`: File identifier (first byte)
- `id2::Vector{UInt8}`: File identifier (remaining bytes)
- `text1::String`: Subject information
- `text2::String`: Recording information
- `start_date::String`: Recording start date (DD.MM.YYYY)
- `start_time::String`: Recording start time (HH.MM.SS)
- `num_bytes_header::Int`: Header size in bytes
- `data_format::String`: Data format identifier (e.g., "EDF+C" for continuous EDF+)
- `num_data_records::Int`: Number of data records
- `duration_data_records::Float64`: Duration of each record in seconds
- `num_channels::Int`: Number of channels (including status channel)
- `channel_labels::Vector{String}`: Channel names/labels
- `transducer_type::Vector{String}`: Transducer type for each channel
- `channel_unit::Vector{String}`: Physical units for each channel
- `physical_min::Vector{Int}`: Physical minimum values
- `physical_max::Vector{Int}`: Physical maximum values
- `digital_min::Vector{Int}`: Digital minimum values
- `digital_max::Vector{Int}`: Digital maximum values
- `pre_filter::Vector{String}`: Pre-filtering information
- `num_samples::Vector{Int}`: Number of samples per record per channel
- `reserved::Vector{String}`: Reserved header space
- `scale_factor::Vector{Float32}`: Scale factors for data conversion
- `offset::Vector{Float32}`: Physical offsets for data conversion
- `sample_rate::Vector{Int}`: Sampling rate for each channel

# Notes
- The last channel is always the status/trigger channel
- `scale_factor` and `offset` are automatically calculated from physical and digital ranges
- `sample_rate` is calculated from `num_samples` and `duration_data_records`
"""
mutable struct EdfHeader
  id1::Vector{UInt8}
  id2::Vector{UInt8} 
  text1::String
  text2::String
  start_date::String
  start_time::String
  num_bytes_header::Int
  data_format::String
  num_data_records::Int
  duration_data_records::Float64
  num_channels::Int
  channel_labels::Vector{String}
  transducer_type::Vector{String}
  channel_unit::Vector{String}
  physical_min::Vector{Float32}
  physical_max::Vector{Float32}
  digital_min::Vector{Float32}
  digital_max::Vector{Float32}
  pre_filter::Vector{String}
  num_samples::Vector{Int}
  reserved::Vector{String}
  scale_factor::Vector{Float32}
  offset::Vector{Float32}
  sample_rate::Vector{Int}
end

"""
    EdfTriggers

Data structure containing trigger and status channel information.

# Fields
- `raw::Vector{Int16}`: Raw trigger values for each sample
- `idx::Vector{Int}`: Sample indices where triggers occur
- `val::Vector{Int}`: Trigger values at trigger events
- `count::OrderedDict{Int,Int}`: Count of each trigger value
- `time::Matrix{Float64}`: Trigger timing information (value × time)

# Notes
- `raw` contains trigger values for every sample (0 for no trigger)
- `idx` contains sample indices where trigger values change
- `time` matrix has columns: trigger_value, time_since_previous_trigger
"""
mutable struct EdfTriggers
  raw::Vector{Int16}
  idx::Vector{Int}
  val::Vector{Int}
  count::OrderedDict{Int,Int}
  time::Matrix{Float64}
end

"""
    EdfData

Complete data structure containing EDF EDF file data and metadata.

# Fields
- `filename::String`: Source filename
- `header::EdfHeader`: File header information
- `data::Matrix{Float32}`: EEG data matrix (samples × channels)
- `time::StepRangeLen{Float64}`: Time vector for each sample
- `triggers::EdfTriggers`: Trigger event information
- `status::Vector{Int16}`: Status channel values for each sample

# Notes
- `data` matrix excludes the status channel (stored separately in `status`)
- `time` vector starts at 0 and increments by 1/sample_rate
- `status` contains the status channel values (typically 0)
"""
mutable struct EdfData
  filename::String
  header::EdfHeader
  data::Matrix{Float32}
  time::StepRangeLen{Float64}
  triggers::EdfTriggers
  status::Vector{Int16}
end

# Display methods for the types
function Base.show(io::IO, hdr::EdfHeader)
  println(io, "Number of Channels: ", length(hdr.channel_labels) - 1)
  println(io, "Channel Labels: ", join(hdr.channel_labels[1:end-1], ", "))
  println(io, "Number of Data Records: ", hdr.num_data_records)
  println(io, "Sample Rate: ", hdr.sample_rate[1])
end

function Base.show(io::IO, trig::EdfTriggers)
  println(io, "Triggers (Value => Count): ", join(trig.count, ", "))
end

function Base.show(io::IO, dat::EdfData)
  println(io, "Filename: $(dat.filename)")
  print(io, dat.header)
  println(io, "Data Size: $(size(dat.data))")
  println(io, dat.triggers)
end
