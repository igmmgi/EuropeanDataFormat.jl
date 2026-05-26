# EuropeanDataFormat

A Julia package for reading, writing, and processing EDF/EDF+ EEG data files.

## Overview

EDF (European Data Format) files store 16-bit EEG data with metadata including channel information, sampling rates, and trigger events. This package provides comprehensive functionality to work with these files in Julia.

## Features

- **File I/O**: Read and write Edf (\*.edf) files
- **Basic Data Processing**: Crop, downsample, and merge data
- **Channel Management**: Select, delete, and manipulate channels
- **Trigger Analysis**: Extract and analyze trigger events
- **Status Channel**: Handle EDF status channel information

## Quick Start

```julia
using EuropeanDataFormat

# Read a EDF file
dat = read_edf("eeg_data.edf")

# Select specific channels
dat_selected = select_channels_edf(dat, ["Fp1", "Cz", "O1"])

# Crop data to specific time range
dat_cropped = crop_edf(dat, "triggers", [100, 500])

# Downsample data
dat_downsampled = downsample_edf(dat, 2)

# Write modified data
write_edf(dat_downsampled, "processed_data.edf")
```

## Installation

```julia
using Pkg
Pkg.add("EuropeanDataFormat")
```

## Documentation

- [API Reference](@ref)
