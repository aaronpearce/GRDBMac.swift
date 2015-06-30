//
//  SequenceStatement.swift
//  GRDB
//
//  Created by Gwendal Roué on 30/06/2015.
//  Copyright © 2015 Gwendal Roué. All rights reserved.
//

public class RowSequence : Statement, SequenceType {
    public lazy var columnCount: Int = Int(sqlite3_column_count(self.cStatement))
    
    private var _rowGenerator: RowGenerator?
    
    public func generate() -> RowGenerator {
        if let _rowGenerator = _rowGenerator {
            return _rowGenerator
        }
        _rowGenerator = RowGenerator(rowSequence: self)
        return _rowGenerator!
    }
    
    override public func reset() {
        super.reset()
        _rowGenerator = nil
    }
    
    public class RowGenerator : GeneratorType {
        let rowSequence: RowSequence
        
        init(rowSequence: RowSequence) {
            self.rowSequence = rowSequence
        }
        
        public func next() -> Row? {
            let code = sqlite3_step(rowSequence.cStatement)
            switch code {
            case SQLITE_DONE:
                // the statement has finished executing successfully
                return nil
            case SQLITE_ROW:
                // each time a new row of data is ready for processing by the caller.
                return Row(rowSequence: rowSequence)
            default:
                try! Error.checkCResultCode(code, cConnection: rowSequence.cConnection)
                return nil
            }
        }
    }
}
