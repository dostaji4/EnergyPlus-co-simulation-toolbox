# Getting Started with EnergyPlus co-simulation toolbox
## Description
The toolbox facilitates simultaneous simulation of EnergyPlus and Matlab (co-simulation). The main component is the 'mlep' class containing all the necessary tools to configure and run EnergyPlus co-simulation within the Matlab environment. 
## System Requirements
* __Windows__. The toolbox has only been tested for Windows, but considerable preparations for other OS has already been done.
* __EnergyPlus installed__ You can obtain the software here [ https://energyplus.net/](https://energyplus.net/). If you install the EnergyPlus to the default location ('C:\EnergyPlusVx-x-x\') then it might be detected automatically by the toolbox. Please note, that you should always simulate IDF files by the same version of the EnergyPlus with which they were created or you can alternatively upgrade the IDF file by the IDFVersionUpdater (located under 'C:\EnergyPlusVx-x-x\PreProcess\IDFVersionUpdater'). 

## Install 
Download and install the toolbox binary from [https://github.com/dostaji4/EnergyPlus-co-simulation-toolbox/releases](https://github.com/dostaji4/EnergyPlus-co-simulation-toolbox/releases).

## Features
The toolbox contains:
* Parsing of the IDF file to determine co-simulation inputs/outputs.
* Automatic socket communication configuration (on localhost).
* Background start of the EnergyPlus process with output to the Matlab command line.
* System Object implementation usable in Matlab & Simulink. 
* Bus input/output integration for easy Simulink model setup. 
* A 'mlep Bus Creator' block to facilitate Simulink co-simulation input setup. 
## Examples

For detailed Matlab example see
```matlab
open mlepMatlab_example
```
Usage of the System Object functionality in Matlab is demonstrated in 
```matlab
open mlepMatlab_so_example
```
Simulink example is provided in 
```matlab
open mlepSimulink_example.slx
```
