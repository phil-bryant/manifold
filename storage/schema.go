package storage

import _ "embed"

// #R001: Embed schema SQL for runtime schema application.
//go:embed schema.sql
var SchemaSQL string
