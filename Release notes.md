# Release notes

## [todo]
 * Add support for EnergyManagementSystem:OutputVariable
 * EPW source block for Simulink.
 * Bus objects may be stored in a DataDictionary to avoid its residency in 
   the base workspace.
 * epJSON (out = jsondecode(fileread(".epJSON")))

## [unreleased] 

### Added    

### Changed

## [v1.2.3] 

### Added
* Added help link to the EP communication block.
 * Added checking for ExternalInterface being set to PtolemyServer

### Changed
 * Updated IDF files to EnergyPlus version 9.2.
 * Fixed a bug when reading ExternalInterface:Actuator inputs.  
 * Fixed function index link in the documentation. 
 
## [v1.2.2] 

### Added    

### Changed
 * renamed installMlep to setupMlep. Solved a critical bug therein (v1.2.1.1).
 * disabled loading of object properties - until needed or better tested.
 * updated examples to EnergyPlus version 9.1.0
 * disabled IDF simulation with mismatching EnergyPlus version. 
 * updated simulink models to Matlab r18b. It can still be simulated by older Matlab (enable this in Simulink preferences).
  
## [v1.2.1] 

### Added   
 * Better documentation

### Changed
 
## [v1.2]
Bus objects generated in 

### Added 
 * Load and Save routines.  
 
### Changed
 * Bus objects are now loading in the Init function callback. It should solve 
   the '_Missing Bus objects_' issues.
 * Optimized IDF file parsing speed.
 * Initialization no longer triggered from the Simulink mask.
 * Robustified _Vector to Bus_ block callback.

## [v1.1]
Structure of the main Simulink library was changed to support signal names longer then 63 characters.

### Added
 * Bus objects now support signal names longer than 63 characters.
 * Simulation and initialization are now considerably faster. 
 * **Vector to Bus block**. Make a bus out of a appropriately sized vector.
 * Browse buttons in the Simulink block mask.
 
### Changed
 * mlep system object does not work internally with busses anymore. It imposed the 63char. limit and was slow anyway. 
 * Renamed the main simulink block from _EnergyPlus SO_ to **EnergyPlus Simulation**.
 * The working directory is by default the directory of the selected IDF file.
 * IDF and EPW files are no longer required to be on the Matlab searchpath.
 
 ## [v1.0]
This release builds upon a _mlep_ code by Truong Nghiem and Willy Bernal.

 ### Added
 * Parsing of the IDF file to determine co-simulation inputs/outputs.
 * Automatic socket communication configuration (on localhost).
 * Background start of the EnergyPlus process with output to the Matlab command line.
 * System Object implementation usable in Matlab & Simulink.
 * Bus input/output integration for easy Simulink model setup.
 * A 'mlep Bus Creator' block to facilitate Simulink co-simulation input setup.