"""
    EuropeanDataFormat

Julia package for reading, writing, and processing European Data Format (EDF/EDF+) EEG data files.

This package provides functionality to:
- Read EDF files into Julia data structures
- Write Julia data structures back to EDF format
- Crop data by time or trigger events
- Downsample data by integer factors
- Select or reduce the number of channels
- Merge multiple EDF files
- Process trigger and status channel information

# File Format
EDF/EDF+ files store 16-bit EEG data with metadata including channel information,
sampling rates, and trigger events. See the [EDF specification](https://www.edfplus.info/)
for detailed format information.

# Quick Start
```julia
using EuropeanDataFormat

# Read a EDF file
dat = read_edf("eeg_data.edf")

# Select specific channels
dat_selected = select_channels_edf(dat, ["Fp1", "Cz", "O1"])

# Crop data to specific time range
dat_cropped = crop_edf(dat, "triggers", [100, 200])

# Write modified data
write_edf(dat_cropped, "processed_data.edf")
```

# License
This package is licensed under the MIT License.
"""
module EuropeanDataFormat

using DSP
using Logging
using OrderedCollections

# Include organized module files
include("types.jl")
include("processing.jl")
include("channels.jl")
include("io.jl")

export
  crop_edf!,
  crop_edf,
  delete_channels_edf!,
  delete_channels_edf,
  downsample_edf!,
  downsample_edf,
  merge_edf,
  read_edf,
  recode_triggers!,
  recode_triggers,
  select_channels_edf!,
  select_channels_edf,
  write_edf

end # module
