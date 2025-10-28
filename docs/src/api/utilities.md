# Utilities API Reference

Helper functions for working with DBN data.

## Price Conversions

DBN uses fixed-point arithmetic for prices. These functions convert between fixed-point and floating-point representations.

```@docs
price_to_float
float_to_price
```

### Usage Examples

```julia
using DBN

# Convert DBN fixed-point price to float
fixed_price = 1005000  # 100.5000 in fixed-point
float_price = price_to_float(fixed_price)  # 100.5

# Convert float to DBN fixed-point
price = 100.50
fixed = float_to_price(price)  # 1005000
```

### Fixed-Point Scale

DBN prices use a fixed-point scale:
```julia
FIXED_PRICE_SCALE = 10000  # 4 decimal places
```

So a price of `1005000` represents `1005000 / 10000 = 100.5000`.

## Timestamp Conversions

DBN uses nanosecond timestamps (Int64). These functions convert to/from Julia DateTime objects.

```@docs
datetime_to_ts
ts_to_datetime
ts_to_date_time
date_time_to_ts
to_nanoseconds
```

### Usage Examples

```julia
using DBN, Dates

# DateTime to nanoseconds
dt = DateTime(2024, 1, 1, 9, 30, 0)
ts = datetime_to_ts(dt)  # Nanoseconds since Unix epoch

# Nanoseconds to DateTime
timestamp = 1704067200000000000
dt = ts_to_datetime(timestamp)  # DateTime(2024, 1, 1, 0, 0, 0)

# Format timestamp
formatted = Dates.format(ts_to_datetime(timestamp), "yyyy-mm-dd HH:MM:SS")
```

### Timestamp Precision

DBN timestamps are in **nanoseconds** since Unix epoch (1970-01-01 00:00:00 UTC):
```julia
ts::Int64 = 1704067200000000000
# └─ nanoseconds since 1970-01-01
```

Julia `DateTime` has millisecond precision, so nanosecond timestamps are truncated when converting.

## Other Utilities

```@docs
record_length_bytes
```

## Constants

### Price Constants

```julia
FIXED_PRICE_SCALE::Int64 = 10000  # Scale factor for fixed-point prices
UNDEF_PRICE::Int64        # Undefined price sentinel value
```

### Size Constants

```julia
UNDEF_ORDER_SIZE::UInt32  # Undefined size sentinel value
```

### Timestamp Constants

```julia
UNDEF_TIMESTAMP::UInt64   # Undefined timestamp sentinel value
```

### Version

```julia
DBN_VERSION::UInt8 = 3    # Supported DBN version
```

## Working with Sentinel Values

DBN uses special sentinel values to indicate undefined/missing data:

```julia
using DBN

# Check for undefined price
if trade.price == UNDEF_PRICE
    println("Price not available")
end

# Check for undefined timestamp
if record.ts_recv == UNDEF_TIMESTAMP
    println("Receive timestamp not available")
end

# Check for undefined size
if order.size == UNDEF_ORDER_SIZE
    println("Size not specified")
end
```

## See Also

- [Types](types.md) - Message type reference
- [Conversion Guide](../guide/conversion.md) - Format conversion guide
- [Databento Documentation](https://databento.com/docs/) - Format specifications
