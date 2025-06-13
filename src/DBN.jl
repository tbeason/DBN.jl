"""
    DBN.jl

    DBN.jl is a Julia package for reading and writing Databento Binary Encoding (DBN) files.
"""
module DBN

# All using statements at the top
using Dates
using CRC32c
using CodecZstd
using TranscodingStreams
using EnumX

# Include all the component files
include("types.jl")
include("messages.jl")
include("decode.jl")
include("encode.jl")
include("streaming.jl")

# Exports
export DBNDecoder, DBNEncoder, read_dbn, write_dbn
export Metadata, DBNHeader, RecordHeader, DBNTimestamp
export MBOMsg, TradeMsg, MBP1Msg, MBP10Msg, OHLCVMsg, StatusMsg, ImbalanceMsg, StatMsg
export CMBP1Msg, CBBO1sMsg, CBBO1mMsg, TCBBOMsg, BBO1sMsg, BBO1mMsg
export ErrorMsg, SymbolMappingMsg, SystemMsg, InstrumentDefMsg
export DBNStream, DBNStreamWriter, write_record!, close_writer!
export compress_dbn_file, compress_daily_files
export Schema, Compression, Encoding, SType, RType, Action, Side, InstrumentClass
export price_to_float, float_to_price, ts_to_datetime, datetime_to_ts, ts_to_date_time, date_time_to_ts, to_nanoseconds
export DBN_VERSION, FIXED_PRICE_SCALE, UNDEF_PRICE, UNDEF_ORDER_SIZE, UNDEF_TIMESTAMP
export BidAskPair, VersionUpgradePolicy, DatasetCondition
export write_header, read_header!, write_record, read_record, finalize_encoder

end  # module DBN