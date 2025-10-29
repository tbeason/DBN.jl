# Enums API Reference

Enumeration types used throughout DBN.jl.

## Schema Types

```@docs
Schema
```

### Available Schemas

The `Schema` enum defines the available data schemas:

- `MBO` - Market-by-order
- `MBP_1` - Market-by-price (top of book)
- `MBP_10` - Market-by-price (10 levels)
- `TBBO` - Top-of-book BBO
- `TRADES` - Trade messages
- `OHLCV_1S`, `OHLCV_1M`, `OHLCV_1H`, `OHLCV_1D` - OHLCV bars at different intervals
- `STATUS` - Status messages
- `IMBALANCE` - Imbalance messages
- And more...

For complete schema details, see [Databento Schemas Documentation](https://databento.com/docs/schemas-and-data-formats/whats-a-schema).

## Record Types

```@docs
RType
```

Record types identify the message type in the binary format. Common values:
- `MBO_MSG` - Market-by-order message
- `TRADE_MSG` - Trade message
- `MBP_0_MSG` - MBP level 0 (trades)
- `MBP_1_MSG` - MBP level 1
- `MBP_10_MSG` - MBP level 10
- `OHLCV_1M_MSG` - 1-minute OHLCV
- And more...

## Symbol Types

```@docs
SType
```

Symbol types specify how instruments are identified:
- `RAW_SYMBOL` - Raw symbol string
- `INSTRUMENT_ID` - Numeric instrument ID
- `PARENT` - Parent instrument
- And more...

## Action Types

```@docs
Action
```

Action types for order and trade messages:
- `ADD` - Order added to book
- `MODIFY` - Order modified
- `CANCEL` - Order cancelled
- `TRADE` - Trade execution
- `CLEAR` - Order cleared
- And more...

## Side Types

```@docs
Side
```

Side of market:
- `BID` - Buy side
- `ASK` - Sell side
- `NONE` - No side specified

## Compression Types

```@docs
Compression
```

Compression formats:
- `NONE` - No compression
- `ZSTD` - Zstandard compression

## Encoding Types

```@docs
Encoding
```

File encoding formats:
- `DBN` - Databento Binary Encoding
- `CSV` - Comma-separated values
- `JSON` - JSON format

## Instrument Class

```@docs
InstrumentClass
```

Instrument classification:
- `STOCK` - Equity
- `FUTURE` - Futures contract
- `OPTION` - Options contract
- `FX_SPOT` - Foreign exchange spot
- And more...

## Usage Examples

### Working with Schemas

```julia
using DBN

# Check schema type
if metadata.schema == Schema.TRADES
    trades = read_trades(filename)
end

# Schema to string
schema_name = string(Schema.TRADES)  # "TRADES"
```

### Working with Actions

```julia
# Filter by action
foreach_mbo("file.dbn") do mbo
    if mbo.action == Action.ADD
        # Handle new order
    elseif mbo.action == Action.CANCEL
        # Handle cancellation
    end
end
```

### Working with Sides

```julia
# Count by side
bid_count = 0
ask_count = 0

foreach_trade("file.dbn") do trade
    if trade.side == Side.BID
        bid_count += 1
    else
        ask_count += 1
    end
end
```

## See Also

- [Types](types.md) - Message type reference
- [Databento Schema Documentation](https://databento.com/docs/schemas-and-data-formats) - Schema specifications
