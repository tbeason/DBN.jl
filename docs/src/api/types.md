# Types API Reference

DBN message types and supporting structures.

## Core Types

```@docs
DBNDecoder
DBNEncoder
Metadata
DBNHeader
RecordHeader
DBNTimestamp
```

## Trade Messages

```@docs
TradeMsg
```

## Market-by-Order Messages

```@docs
MBOMsg
```

## Market-by-Price Messages

```@docs
MBP1Msg
MBP10Msg
BidAskPair
```

## OHLCV Messages

```@docs
OHLCVMsg
```

## Consolidated Market Data

```@docs
CMBP1Msg
CBBO1sMsg
CBBO1mMsg
TCBBOMsg
BBO1sMsg
BBO1mMsg
```

## Status and Information Messages

```@docs
StatusMsg
ImbalanceMsg
StatMsg
ErrorMsg
SymbolMappingMsg
SystemMsg
InstrumentDefMsg
```

## Supporting Types

```@docs
VersionUpgradePolicy
DatasetCondition
```

## Message Structure

All DBN messages follow a common pattern:

1. **Record Header** (`RecordHeader`): Metadata about the record
   - `length`: Record length in 4-byte units
   - `rtype`: Record type identifier
   - `publisher_id`: Data publisher identifier
   - `instrument_id`: Instrument identifier
   - `ts_event`: Event timestamp (nanoseconds)

2. **Message Fields**: Schema-specific fields

### Field Types

- **Prices**: Fixed-point Int64 (use `price_to_float` / `float_to_price`)
- **Timestamps**: Nanoseconds since Unix epoch (Int64)
- **Sizes**: UInt32 for quantities
- **IDs**: UInt32 or UInt64 for identifiers
- **Enums**: Action, Side, Schema, etc.

## Field Meanings

For detailed field meanings and specifications, see:
- [Databento Schema Documentation](https://databento.com/docs/schemas-and-data-formats)
- [DBN Format Specification](https://databento.com/docs/standards-and-conventions/databento-binary-encoding)

## See Also

- [Enums](enums.md) - Enum types used in messages
- [Utilities](utilities.md) - Helper functions for working with types
- [Reading Guide](../guide/reading.md) - How to read different message types
