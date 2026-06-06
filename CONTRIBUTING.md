# Contributing

Thanks for helping improve `mac-dev-clean`.

## Development

Run the test suite from the repository root:

```sh
PYTHONPATH=src python3 -m unittest discover -s tests
```

Run a bytecode compile check:

```sh
PYTHONPYCACHEPREFIX=/private/tmp/mac-dev-clean-pycache python3 -m compileall -q src tests
```

## Safety Rules

This project works near developer cache directories, so changes should keep the safety model boring and explicit:

- Scans and reports must never delete data.
- Destructive commands must require an explicit category or action.
- Prefer official tools such as `xcrun simctl` over deleting tool internals directly.
- Add or update tests for every new deletion path.
- Keep dry-run output accurate enough that a user can see what would be affected.

## License

By contributing, you agree that your contributions are licensed under the MIT License.

