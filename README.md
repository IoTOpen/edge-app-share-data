# edge-app-share-data

Edge app for sharing devices and their functions cross installations.

The EdgeApp should be installed on the source installation and the configuration is done there. There is no need for and edge-client on the target installations.

## Configuration

The EdgeApp needs the following configuration

### Target installation
The ID of the installation that the mirrored Devices are created.

### API-Key
An API-Key to a user with access to the Target installation. It doesn't have to have access to the source installation.

### Devices
A list of devices that should be mirrored.

## How it works

The App creates a device in the target installation that is a copy of the one on the source installation. Whenever new data comes to the functions of the source device they are also sent to the target functions. Only data to topics defined as topic_* on the source device are mirrored.

The target device and its function may be modified to fit the needs in the target installation but `source.device` and `source.function` cannot be removed or changed since that will result in another copy being created.

Modification done on the source will not be mirrored to the copy unless the copy first is removed.