# API Reference

## Module

```@docs
EuropeanDataFormat
```

## Data Structures

```@docs
EuropeanDataFormat.EdfHeader
EuropeanDataFormat.EdfTriggers
EuropeanDataFormat.EdfData
```

## File I/O Functions

### Reading EDF Files

```@docs
EuropeanDataFormat.read_edf
```

### Writing EDF Files

```@docs
EuropeanDataFormat.write_edf
```

## Data Processing Functions

### Cropping and Slicing

```@docs
EuropeanDataFormat.crop_edf
EuropeanDataFormat.crop_edf!
EuropeanDataFormat.time_range
EuropeanDataFormat.trigger_info
```

### Downsampling

```@docs
EuropeanDataFormat.downsample_edf
EuropeanDataFormat.downsample_edf!
```

### Merging

```@docs
EuropeanDataFormat.merge_edf
```

### Trigger Manipulation

```@docs
EuropeanDataFormat.recode_triggers
EuropeanDataFormat.recode_triggers!
```

## Channel Management Functions

### Channel Selection

```@docs
EuropeanDataFormat.select_channels_edf
EuropeanDataFormat.select_channels_edf!
```

### Channel Deletion

```@docs
EuropeanDataFormat.delete_channels_edf
EuropeanDataFormat.delete_channels_edf!
```

### Channel Utilities

```@docs
EuropeanDataFormat.channel_index
```
