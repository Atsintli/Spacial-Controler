# Spacial-Controler
A SuperCollider-based multi-channel spatial audio environment for sound installations and live performances.

## Overview

This system provides a dynamic spatial audio engine with multiple stems/tracks, advanced spatialization algorithms, and spectral processing capabilities. The application includes a graphical user interface for real-time control and offers various modulation techniques for creating immersive soundscapes across 4-channel audio outputs.

## Features

- **4-Channel Spatial Processing**: Designed for quadraphonic speaker arrangements
- **Multiple Modulation Types**: Circular (LFSaw) and random (LFNoise1) spatial movements
- **Spectral-Based Effects**: Dynamic processing based on spectral centroid analysis
- **Per-Track Control**: Individual rate, pan, and volume settings for each audio file
- **Global Effects**: Spectral-controlled delay with dynamic spatialization
- **Mute/Solo Functionality**: For easy track isolation
- **Real-time GUI**: Comprehensive control interface with responsive visual feedback

## Technical Specifications

- Multi-channel audio playback (4-channel output)
- Spectral-based spatial processing
- Per-track and global delay effects
- Dynamic rate and pan modulation
- Automatic loading of audio files from specified directory

## Requirements

- SuperCollider 3.11+
- Multi-channel audio interface (4+ outputs)
- Audio files in a specified directory

## Usage

1. Configure the audio interface settings in the initialization section
2. Set the path to your audio files directory
3. Run the initialization code
4. Use the GUI to control spatial parameters and effects

## Implementation Details

### Core Components

- `trackPlayer` SynthDef: Handles individual track playback with spatial control
- `pingPongCentroideDelay` SynthDef: Global spectral-based delay effect with spatial movement
- GUI system: Comprehensive control interface for all parameters

### Spatial Algorithms

The system uses two main spatial approaches:
1. **PanAz-based spatialization**: Circular movement with direction control
2. **Spectral-responsive spatial modulation**: Dynamic positioning based on spectral content

### Delay Effects

- Individual track delays with customizable parameters
- Global spectral-reactive delay effect with centroid analysis
- Wet/dry control for effect intensity

## Global Controls

- Global pan rate multiplier
- Reset functionality for returning to original settings
- Randomization options for spatial settings and rates
- Lag time adjustment for smooth transitions

## Tips for Optimal Use

- Experiment with different modulation types for varied spatial experiences
- Use the global spectral delay for more organic movement patterns
- Combine circular and random movement types across different tracks
- For complex audio material, reduce the centroid scale for more subtle responses

## License

[MIT License]

## Credits

Developed by [Your Name]
