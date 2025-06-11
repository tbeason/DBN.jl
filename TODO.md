# DBN.jl Testing TODO List

## Phase 1: Basic Module Setup and Loading ✅

- [x] Verify the module loads without syntax errors
- [x] Check all required dependencies are in Project.toml (Dates, CRC32c, CodecZstd, TranscodingStreams)
- [x] Ensure all exports are properly defined
- [x] Test that all enums can be instantiated

## Phase 2: Struct and Type Testing ✅

- [x] Test creating instances of simple structs:
  - [x] RecordHeader
  - [x] BidAskPair
  - [x] VersionUpgradePolicy
  - [x] DatasetCondition
- [x] Test creating metadata struct
- [x] Test creating each message type struct:
  - [x] MBOMsg
  - [x] TradeMsg
  - [x] MBP1Msg
  - [x] MBP10Msg
  - [x] OHLCVMsg
  - [x] StatusMsg
  - [x] ImbalanceMsg
  - [x] StatMsg
  - [x] InstrumentDefMsg

## Phase 3: Utility Function Testing ✅

- [x] Test price conversion functions:
  - [x] price_to_float with normal prices
  - [x] price_to_float with UNDEF_PRICE
  - [x] float_to_price with normal values
  - [x] float_to_price with NaN/Inf
- [x] Test timestamp conversion functions:
  - [x] DBNTimestamp constructor
  - [x] to_nanoseconds
  - [x] ts_to_datetime
  - [x] datetime_to_ts
  - [x] ts_to_date_time
  - [x] date_time_to_ts

## Phase 4: Basic Read/Write Testing (No Compression) ✅

- [x] Create a minimal DBN file writer test:
  - [x] Write DBN header
  - [x] Write a single TradeMsg record
  - [x] Verify file is created
- [x] Create a minimal DBN file reader test:
  - [x] Read the file created above
  - [x] Verify header is parsed correctly
  - [x] Verify record is read correctly
- [x] Test round-trip (write then read):
  - [x] Write multiple record types
  - [x] Read them back
  - [x] Verify data integrity

## Phase 5: Record Type Read/Write Testing

- [ ] Test writing and reading each message type:
  - [ ] MBOMsg serialization/deserialization
  - [ ] TradeMsg serialization/deserialization
  - [ ] MBP1Msg serialization/deserialization
  - [ ] MBP10Msg serialization/deserialization
  - [ ] OHLCVMsg serialization/deserialization
  - [ ] StatusMsg serialization/deserialization
  - [ ] ImbalanceMsg serialization/deserialization
  - [ ] StatMsg serialization/deserialization
  - [ ] InstrumentDefMsg serialization/deserialization (complex with many fields)

## Phase 6: Compression Testing

- [ ] Test writing compressed DBN file:
  - [ ] Create encoder with ZSTD compression
  - [ ] Write records
  - [ ] Verify compressed file is smaller
- [ ] Test reading compressed DBN file:
  - [ ] Read compressed file
  - [ ] Verify records match original
- [ ] Test compress_dbn_file function:
  - [ ] Compress existing uncompressed file
  - [ ] Verify compression stats returned
  - [ ] Test delete_original option

## Phase 7: Streaming Writer Testing

- [ ] Test DBNStreamWriter creation
- [ ] Test write_record! with timestamp tracking
- [ ] Test auto-flush functionality
- [ ] Test close_writer! and header update
- [ ] Verify timestamps are correctly updated in metadata

## Phase 8: Missing Functionality Testing

- [ ] Implement and test DBNStream iterator
- [ ] Test ErrorMsg, SymbolMappingMsg, SystemMsg write operations
- [ ] Test batch compression with compress_daily_files

## Phase 9: Edge Cases and Error Handling

- [ ] Test reading invalid/corrupted files
- [ ] Test writing to read-only locations
- [ ] Test handling of empty files
- [ ] Test very large files
- [ ] Test files with mixed record types
- [ ] Test boundary values for timestamps and prices

## Phase 10: Integration and Performance Testing

- [ ] Test with sample DBN files from reference implementation (located in test/data)
- [ ] Benchmark read/write performance
- [ ] Memory usage profiling
- [ ] Test thread safety of compress_daily_files

## Phase 11: Compliance Testing

- [ ] Compare output with reference implementation
- [ ] Validate all record layouts match DBN v2 spec
- [ ] Test interoperability with official DBN tools

## Implementation Notes

### Test Data Creation Strategy

1. Start with synthetic test data for basic functionality
2. Create minimal valid DBN files for each test case
3. Use reference implementation samples for compliance testing

### Testing Approach

1. Create a test/ directory with organized test files (located in test/data)
2. Use Julia's built-in Test framework
3. Start with the simplest tests and build up
4. Each phase should be completed before moving to the next

### Known Issues to Watch For

- The `read_dbn` and `write_dbn` convenience functions need error handling
- DBNStream is referenced but not implemented
- Some message types (Error, SymbolMapping, System) don't have write implementations
- File position handling in streaming writer header update might have issues

### Priority Order

1. Get basic module loading working (Phase 1)
2. Ensure structs are valid (Phase 2)
3. Test core read/write without compression (Phase 4)
4. Add compression support (Phase 6)
5. Complete missing functionality (Phase 8)
