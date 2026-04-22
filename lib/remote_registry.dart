/// remote_registry — CDN-backed config registry client for Flutter.
library;

export 'src/remote_registry.dart' show RemoteRegistry, RegistryInitMode;
export 'src/errors.dart'
    show
        RegistryException,
        RegistryNetworkException,
        RegistryIntegrityException,
        RegistryFileNotFoundException,
        RegistryUnavailableException;
