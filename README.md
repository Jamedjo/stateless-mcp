# stateless-mcp

Serves the [Model Context Protocol](https://modelcontextprotocol.io/specification/2026-07-28) from Ruby, the stateless way: every request carries its own protocol version and is answered on its own, with a plain JSON body. Nothing holds a session or a stream open, so any process behind a load balancer can take any call.

Two gems live in this repository and are released together, always at the same version:

| Gem | For |
|---|---|
| [`stateless-mcp`](stateless-mcp) | Any Rack app. Depends only on the [`mcp`](https://github.com/modelcontextprotocol/ruby-sdk) gem and `rack` |
| [`stateless-mcp-rails`](stateless-mcp-rails) | Rails apps, where a tool is an ordinary controller action |

> **Status:** unreleased, and under construction. Nothing is on RubyGems yet.

## Development

```sh
bundle install
(cd stateless-mcp && bundle exec rspec)
(cd stateless-mcp-rails && bundle exec rspec)
bundle exec rubocop
```

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or https://www.apache.org/licenses/LICENSE-2.0)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or https://opensource.org/licenses/MIT)

at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
