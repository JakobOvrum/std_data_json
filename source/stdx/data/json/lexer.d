/**
 * Provides JSON lexing facilities.
 *
 * Synopsis:
 * ---
 * // Lex a JSON string into a lazy range of tokens
 * auto tokens = lexJSON(`{"name": "Peter", "age": 42}`);
 *
 * with (JSONToken) {
 *     assert(tokens.map!(t => t.kind).equal(
 *         [Kind.objectStart, Kind.string, Kind.colon, Kind.string, Kind.comma,
 *         Kind.string, Kind.colon, Kind.number, Kind.objectEnd]));
 * }
 *
 * // Get detailed information
 * tokens.popFront(); // skip the '{'
 * assert(tokens.front.string == "name");
 * tokens.popFront(); // skip "name"
 * tokens.popFront(); // skip the ':'
 * assert(tokens.front.string == "Peter");
 * assert(tokens.front.location.line == 0);
 * assert(tokens.front.location.column == 9);
 * ---
 *
 * Credits:
 *   Support for escaped UTF-16 surrogates was contributed to the original
 *   vibe.d JSON module by Etienne Cimon. The number parsing code is based
 *   on the version contained in Andrei Alexandrescu's "std.jgrandson"
 *   module draft.
 *
 * Copyright: Copyright 2012 - 2014, Sönke Ludwig.
 * License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Sönke Ludwig
 * Source:    $(PHOBOSSRC std/data/json/lexer.d)
 */
module stdx.data.json.lexer;
@safe:

import std.range;
import std.traits : isIntegral, isSomeChar, isSomeString;
import stdx.data.json.foundation;


/**
 * Returns a lazy range of tokens corresponding to the given JSON input string.
 *
 * The input must be a valid JSON string, given as an input range of either
 * characters, or of integral values. In case of integral types, the input
 * ecoding is assumed to be a superset of ASCII that is parsed unit by unit.
 *
 * For inputs of type $(D string) and of type $(D immutable(ubyte)[]), all
 * string literals will be stored as slices into the original string. String
 * literals containung escape sequences will be unescaped on demand when
 * $(D JSONString.value) is accessed.
 *
 * Throws:
 *   Without $(D LexOptions.noThrow), a $(D JSONException) is thrown as soon as
 *   an invalid token is encountered.
 *
 *   If $(D LexOptions.noThrow) is given, lexJSON does not throw any exceptions,
 *   apart from letting through any exceptins thrown by the input range.
 *   Instead, a token with kind $(D JSONToken.Kind.error) is generated as the
 *   last token in the range.
 */
JSONLexerRange!(Input, options) lexJSON
    (LexOptions options = LexOptions.init, Input)
    (Input input, string filename = null)
    if (isStringInputRange!Input || isIntegralInputRange!Input)
{
    return JSONLexerRange!(Input, options)(input, filename);
}

///
unittest
{
    auto rng = lexJSON(`{ "hello": 1.2, "world":[1, true, null]}`);
    with (JSONToken)
    {
        assert(rng.map!(t => t.kind).equal(
            [Kind.objectStart, Kind.string, Kind.colon, Kind.number, Kind.comma,
            Kind.string, Kind.colon, Kind.arrayStart, Kind.number, Kind.comma,
            Kind.boolean, Kind.comma, Kind.null_, Kind.arrayEnd,
            Kind.objectEnd]));
    }
}

///
unittest
{
    auto rng = lexJSON("true\n   false null\r\n  1.0\r \"test\"");
    rng.popFront();
    assert(rng.front.boolean == false);
    assert(rng.front.location.line == 1 && rng.front.location.column == 3);
    rng.popFront();
    assert(rng.front.kind == JSONToken.Kind.null_);
    assert(rng.front.location.line == 1 && rng.front.location.column == 9);
    rng.popFront();
    assert(rng.front.number == 1.0);
    assert(rng.front.location.line == 2 && rng.front.location.column == 2);
    rng.popFront();
    assert(rng.front.string == "test");
    assert(rng.front.location.line == 3 && rng.front.location.column == 1);
    rng.popFront();
    assert(rng.empty);
}

unittest
{
    import std.exception;
    assertThrown(lexJSON(`trui`).front); // invalid token
    assertThrown(lexJSON(`fal`).front); // invalid token
    assertThrown(lexJSON(`falsi`).front); // invalid token
    assertThrown(lexJSON(`nul`).front); // invalid token
    assertThrown(lexJSON(`nulX`).front); // invalid token
    assertThrown(lexJSON(`0.e`).front); // invalid number
    assertThrown(lexJSON(`xyz`).front); // invalid token
}

unittest { // test built-in UTF validation
    import std.exception;

    static void test_invalid(immutable(ubyte)[] str)
    {
        assertThrown(lexJSON(str).front);
        assertNotThrown(lexJSON(cast(string)str).front);
    }

    test_invalid(['"', 0xFF, '"']);
    test_invalid(['"', 0xFF, 'x', '"']);
    test_invalid(['"', 0xFF, 'x', '\\', 't','"']);
    test_invalid(['"', '\\', 't', 0xFF,'"']);
    test_invalid(['"', '\\', 't', 0xFF,'x','"']);

    static void testw_invalid(immutable(ushort)[] str)
    {
        import std.conv;
        assertThrown(lexJSON(str).front, str.to!string);

        // Invalid UTF sequences can still throw in the non-validating case,
        // because UTF-16 is converted to UTF-8 internally, so we don't test
        // this case:
        // assertNotThrown(lexJSON(cast(wstring)str).front);
    }

    static void testw_valid(immutable(ushort)[] str)
    {
        import std.conv;
        assertNotThrown(lexJSON(str).front, str.to!string);
        assertNotThrown(lexJSON(cast(wstring)str).front);
    }

    testw_invalid(['"', 0xD800, 0xFFFF, '"']);
    testw_invalid(['"', 0xD800, 0xFFFF, 'x', '"']);
    testw_invalid(['"', 0xD800, 0xFFFF, 'x', '\\', 't','"']);
    testw_invalid(['"', '\\', 't', 0xD800, 0xFFFF,'"']);
    testw_invalid(['"', '\\', 't', 0xD800, 0xFFFF,'x','"']);
    testw_valid(['"', 0xE000, '"']);
    testw_valid(['"', 0xE000, 'x', '"']);
    testw_valid(['"', 0xE000, 'x', '\\', 't','"']);
    testw_valid(['"', '\\', 't', 0xE000,'"']);
    testw_valid(['"', '\\', 't', 0xE000,'x','"']);
}


/**
 * A lazy input range of JSON tokens.
 *
 * This range type takes an input string range and converts it into a range of
 * $(D JSONToken) values.
 *
 * See $(D lexJSON) for more information.
*/
struct JSONLexerRange(Input, LexOptions options = LexOptions.init)
    if (isStringInputRange!Input || isIntegralInputRange!Input)
{
    import std.string : representation;

    static if (isSomeString!Input)
        alias InternalInput = typeof(Input.init.representation);
    else
        alias InternalInput = Input;

    static if (typeof(InternalInput.init.front).sizeof > 1)
        alias CharType = dchar;
    else
        alias CharType = char;

    private
    {
        InternalInput _input;
        JSONToken _front;
        Location _loc;
        string _error;
    }

    /**
     * Constructs a new token stream.
     */
    this(Input input, string filename = null)
    {
        _input = cast(InternalInput)input;
        _front.location.file = filename;
    }

    /**
     * Returns a copy of the underlying input range.
     */
    @property Input input() { return cast(Input)_input; }

    /**
     * The current location of the lexer.
     */
    @property Location location() const { return _loc; }

    /**
     * Determines if the token stream has been exhausted.
     */
    @property bool empty()
    {
        if (_front.kind != JSONToken.Kind.none) return false;
        if (_input.empty) return true;
        skipWhitespace();
        return _input.empty;
    }

    /**
     * Returns the current token in the stream.
     */
    @property ref const(JSONToken) front()
    {
        ensureFrontValid();
        return _front;
    }

    /**
     * Skips to the next token.
     */
    void popFront()
    {
        ensureFrontValid();

        // make sure an error token is the last token in the range
        if (_front.kind == JSONToken.Kind.error)
        {
            // clear the input
            _input = InternalInput.init;
            assert(_input.empty);
        }

        _front.kind = JSONToken.Kind.none;
    }

    private void ensureFrontValid()
    {
        assert(!empty, "Reading from an empty JSONLexerRange.");
        if (_front.kind == JSONToken.Kind.none)
        {
            readToken();
            assert(_front.kind != JSONToken.Kind.none);

            static if (!(options & LexOptions.noThrow))
                enforceJson(_front.kind != JSONToken.Kind.error, _error, _loc);
        }
    }

    private void readToken()
    {
        import std.algorithm : skipOver;

        void skipChar()
        {
            _input.popFront();
            static if (!(options & LexOptions.noTrackLocation)) _loc.column++;
        }


        skipWhitespace();

        assert(!_input.empty, "Reading JSON token from empty input stream.");

        _front.location = _loc;

        string kw;

        switch (_input.front)
        {
            default:
                setError("Malformed token");
                return;
            case 'f': kw = "false"; _front.boolean = false; goto parse_kw;
            case 't': kw = "true"; _front.boolean = true; goto parse_kw;
            case 'n': kw = "null"; _front.kind = JSONToken.Kind.null_; goto parse_kw;
            case '"': parseString(); break;
            case '0': .. case '9': case '-': parseNumber(); break;
            case '[': skipChar(); _front.kind = JSONToken.Kind.arrayStart; break;
            case ']': skipChar(); _front.kind = JSONToken.Kind.arrayEnd; break;
            case '{': skipChar(); _front.kind = JSONToken.Kind.objectStart; break;
            case '}': skipChar(); _front.kind = JSONToken.Kind.objectEnd; break;
            case ':': skipChar(); _front.kind = JSONToken.Kind.colon; break;
            case ',': skipChar(); _front.kind = JSONToken.Kind.comma; break;

            static if (options & LexOptions.specialFloatLiterals)
            {
                case 'N', 'I': parseNumber(); break;
            }
        }

        skipWhitespace();
        return;

		parse_kw:
            if (_input.skipOver(kw))
            {
                static if (!(options & LexOptions.noTrackLocation)) _loc.column += kw.length;
            }
            else setError("Invalid keyord");
    }

    private void skipWhitespace()
    {
        while (!_input.empty)
        {
            static if (!(options & LexOptions.noTrackLocation))
            {
                switch (_input.front)
                {
                    default: return;
                    case '\r': // Mac and Windows line breaks
                        _loc.line++;
                        _loc.column = 0;
                        _input.popFront();
                        if (!_input.empty && _input.front == '\n')
                            _input.popFront();
                        break;
                    case '\n': // Linux line breaks
                        _loc.line++;
                        _loc.column = 0;
                        _input.popFront();
                        break;
                    case ' ', '\t':
                        _loc.column++;
                        _input.popFront();
                        break;
                }
            }
            else
            {
                switch (_input.front)
                {
                    default: return;
                    case '\r', '\n', ' ', '\t':
                        _input.popFront();
                        break;
                }
            }
        }
    }

    private void parseString()
    {
        static if (is(Input == string) || is(Input == immutable(ubyte)[]))
        {
            InternalInput lit;
            if (skipStringLiteral!(!(options & LexOptions.noTrackLocation))(_input, lit, _error, _loc.column))
            {
                auto litstr = cast(string)lit;
                static if (!isSomeChar!(typeof(Input.init.front))) {
                    import std.encoding;
                    if (!()@trusted{ return isValid(litstr); }()) {
                        setError("Invalid UTF sequence in string literal.");
                        return;
                    }
                }
                JSONString js;
                js.rawValue = litstr;
                _front.string = js;
            }
            else _front.kind = JSONToken.Kind.error;
        }
        else
        {
            bool appender_init = false;
            Appender!string dst;
            string slice;

            void initAppender()
            @safe {
                dst = appender!string();
                appender_init = true;
            }

            if (unescapeStringLiteral!(!(options & LexOptions.noTrackLocation), isSomeChar!(typeof(Input.init.front)))(
                    _input, dst, slice, &initAppender, _error, _loc.column
                ))
            {
                if (!appender_init) _front.string = slice;
                else _front.string = dst.data;
            }
            else _front.kind = JSONToken.Kind.error;
        }
    }

    private void parseNumber()
    {
        import std.algorithm : among;
        import std.ascii;
        import std.bigint;
        import std.math;
        import std.string;
        import std.traits;

        assert(!_input.empty, "Passed empty range to parseNumber");

        void skipChar()
        {
            _input.popFront();
            static if (!(options & LexOptions.noTrackLocation)) _loc.column++;
        }


        static if (options & (LexOptions.useBigInt/*|LexOptions.useDecimal*/))
            BigInt int_part = 0;
        else static if (options & LexOptions.useLong)
            long int_part = 0;
        else
            double int_part = 0;
        bool neg = false;

        void setInt()
        {
            if (neg) int_part = -int_part;
            static if (options & LexOptions.useBigInt)
            {
                static if (options & LexOptions.useLong)
                {
                    if (int_part >= long.min && int_part <= long.max) _front.number = int_part.toLong();
                    else _front.number = int_part;
                }
                else _front.number = int_part;
            }
            //else static if (options & LexOptions.useDecimal) _front.number = Decimal(int_part, 0);
            else _front.number = int_part;
        }


        // negative sign
        if (_input.front == '-')
        {
            skipChar();
            neg = true;
        }

        // support non-standard float special values
        static if (options & LexOptions.specialFloatLiterals)
        {
            import std.algorithm : skipOver;
            if (!_input.empty) {
                if (_input.front == 'I') {
                    if (_input.skipOver("Infinity"))
                    {
                        static if (!(options & LexOptions.noTrackLocation)) _loc.column += 8;
                        _front.number = neg ? -double.infinity : double.infinity;
                    }
                    else setError("Invalid number, expected 'Infinity'");
                    return;
                }
                if (!neg && _input.front == 'N')
                {
                    if (_input.skipOver("NaN"))
                    {
                        static if (!(options & LexOptions.noTrackLocation)) _loc.column += 3;
                        _front.number = double.nan;
                    }
                    else setError("Invalid number, expected 'NaN'");
                    return;
                }
            }
        }

        // integer part of the number
        if (_input.empty || !_input.front.isDigit())
        {
            setError("Invalid number, expected digit");
            return;
        }

        if (_input.front == '0')
        {
            skipChar();
            if (_input.empty) // return 0
            {
                setInt();
                return;
            }

            if (_input.front.isDigit)
            {
                setError("Invalid number, 0 must not be followed by another digit");
                return;
            }
        }
        else do
        {
            int_part = int_part * 10 + (_input.front - '0');
            skipChar();
            if (_input.empty) // return integer
            {
                setInt();
                return;
            }
        }
        while (isDigit(_input.front));

        int exponent = 0;

        void setFloat()
        {
            if (neg) int_part = -int_part;
            /*static if (options & LexOptions.useDecimal) _front.number = Decimal(int_part, exponent);
            else*/ _front.number = int_part * 10.0 ^^ exponent;
        }

        // post decimal point part
        assert(!_input.empty);
        if (_input.front == '.')
        {
            skipChar();

            if (_input.empty)
            {
                setError("Missing fractional number part");
                return;
            }

            while (true)
            {
                if (_input.empty)
                {
                    setFloat();
                    return;
                }
                if (!isDigit(_input.front)) break;
                int_part = int_part * 10 + (_input.front - '0');
                exponent--;
                skipChar();
            }
        }

        // exponent
        assert(!_input.empty);
        if (_input.front.among('e', 'E'))
        {
            skipChar();
            if (_input.empty)
            {
                setError("Missing exponent");
                return;
            }

            bool negexp = void;
            if (_input.front == '-')
            {
                negexp = true;
                skipChar();
            }
            else
            {
                negexp = false;
                if (_input.front == '+') skipChar();
            }

            if (_input.empty || !_input.front.isDigit)
            {
                setError("Missing exponent");
                return;
            }

            uint exp = 0;
            while (true)
            {
                exp = exp * 10 + (_input.front - '0');
                skipChar();
                if (_input.empty || !_input.front.isDigit) break;
            }

            if (negexp) exponent -= exp;
            else exponent += exp;
        }

        setFloat();
    }

    void setError(string err)
    {
        _front.kind = JSONToken.Kind.error;
        _error = err;
    }
}

unittest
{
    import std.conv;
    import std.exception;
    import std.string : format, representation;

    static JSONString parseStringHelper(R)(ref R input, ref Location loc)
    {
        auto rng = JSONLexerRange!R(input);
        rng.parseString();
        input = cast(R)rng._input;
        loc = rng._loc;
        return rng._front.string;
    }

    void testResult(string str, string expected, string remaining, bool slice_expected = false)
    {
        { // test with string (possibly sliced result)
            Location loc;
            string scopy = str;
            auto ret = parseStringHelper(scopy, loc);
            assert(ret == expected, ret);
            assert(scopy == remaining);
            assert(&ret.rawValue[0] is &str[0]); // string[] must always slice string literals
            if (slice_expected) assert(&ret[0] is &str[1]);
            assert(loc.line == 0);
            assert(loc.column == str.length - remaining.length, format("%s col %s", str, loc.column));
        }

        { // test with string representation (possibly sliced result)
            Location loc;
            immutable(ubyte)[] scopy = str.representation;
            auto ret = parseStringHelper(scopy, loc);
            assert(ret == expected, ret);
            assert(scopy == remaining);
            assert(&ret.rawValue[0] is &str[0]); // immutable(ubyte)[] must always slice string literals
            if (slice_expected) assert(&ret[0] is &str[1]);
            assert(loc.line == 0);
            assert(loc.column == str.length - remaining.length, format("%s col %s", str, loc.column));
        }

        { // test with dstring (fully duplicated result)
            Location loc;
            dstring scopy = str.to!dstring;
            auto ret = parseStringHelper(scopy, loc);
            assert(ret == expected);
            assert(scopy == remaining.to!dstring);
            assert(loc.line == 0);
            assert(loc.column == str.to!dstring.length - remaining.to!dstring.length, format("%s col %s", str, loc.column));
        }
    }

    testResult(`"test"`, "test", "", true);
    testResult(`"test"...`, "test", "...", true);
    testResult(`"test\n"`, "test\n", "");
    testResult(`"test\n"...`, "test\n", "...");
    testResult(`"test\""...`, "test\"", "...");
    testResult(`"ä"`, "ä", "", true);
    testResult(`"\r\n\\\"\b\f\t\/"`, "\r\n\\\"\b\f\t/", "");
    testResult(`"\u1234"`, "\u1234", "");
    testResult(`"\uD800\udc00"`, "\U00010000", "");
}

unittest
{
    import std.exception;

    void testFail(string str)
    {
        Location loc;
        auto rng1 = JSONLexerRange!(string, LexOptions.init)(str);
        assertThrown(rng1.front);

        auto rng2 = JSONLexerRange!(string, LexOptions.noThrow)(str);
        assertNotThrown(rng2.front);
        assert(rng2.front.kind == JSONToken.Kind.error);
    }

    testFail(`"`); // unterminated string
    testFail(`"\`); // unterminated string escape sequence
    testFail(`"test\"`); // unterminated string
    testFail(`"test'`); // unterminated string
    testFail("\"test\n\""); // illegal control character
    testFail(`"\x"`); // invalid escape sequence
    testFail(`"\u123`); // unterminated unicode escape sequence
    testFail(`"\u123"`); // too short unicode escape sequence
    testFail(`"\u123G"`); // invalid unicode escape sequence
    testFail(`"\u123g"`); // invalid unicode escape sequence
    testFail(`"\uD800"`); // missing surrogate
    testFail(`"\uD800\u"`); // too short second surrogate
    testFail(`"\uD800\u1234"`); // invalid surrogate pair
}

unittest
{
    import std.exception;
    import std.math : approxEqual, isNaN;

    static double parseNumberHelper(LexOptions options, R)(ref R input, ref Location loc)
    {
        auto rng = JSONLexerRange!(R, options & ~LexOptions.noTrackLocation)(input);
        rng.parseNumber();
        input = cast(R)rng._input;
        loc = rng._loc;
        assert(rng._front.kind != JSONToken.Kind.error, rng._error);
        return rng._front.number;
    }

    static void test(LexOptions options = LexOptions.init)(string str, double expected, string remainder)
    {
        import std.conv;
        Location loc;
        auto strcopy = str;
        auto res = parseNumberHelper!options(strcopy, loc);
        assert((res.isNaN && expected.isNaN) || approxEqual(res, expected), () @trusted {return res.to!string;}());
        assert(strcopy == remainder);
        assert(loc.line == 0);
        assert(loc.column == str.length - remainder.length, text(loc.column));
    }

    test("0", 0.0, "");
    test("0 ", 0.0, " ");
    test("-0", 0.0, "");
    test("-0 ", 0.0, " ");
    test("-0e+10 ", 0.0, " ");
    test("123", 123.0, "");
    test("123 ", 123.0, " ");
    test("123.0", 123.0, "");
    test("123.0 ", 123.0, " ");
    test("123.456", 123.456, "");
    test("123.456 ", 123.456, " ");
    test("123.456e1", 1234.56, "");
    test("123.456e1 ", 1234.56, " ");
    test("123.456e+1", 1234.56, "");
    test("123.456e+1 ", 1234.56, " ");
    test("123.456e-1", 12.3456, "");
    test("123.456e-1 ", 12.3456, " ");
    test("123.456e-01", 12.3456, "");
    test("123.456e-01 ", 12.3456, " ");
    test("0.123e-12", 0.123e-12, "");
    test("0.123e-12 ", 0.123e-12, " ");

    test!(LexOptions.specialFloatLiterals)("NaN", double.nan, "");
    test!(LexOptions.specialFloatLiterals)("NaN ", double.nan, " ");
    test!(LexOptions.specialFloatLiterals)("Infinity", double.infinity, "");
    test!(LexOptions.specialFloatLiterals)("Infinity ", double.infinity, " ");
    test!(LexOptions.specialFloatLiterals)("-Infinity", -double.infinity, "");
    test!(LexOptions.specialFloatLiterals)("-Infinity ", -double.infinity, " ");
}

unittest
{
    import std.exception;

    static void testFail(LexOptions options = LexOptions.init)(string str)
    {
        Location loc;
        auto rng1 = JSONLexerRange!(string, options)(str);
        assertThrown(rng1.front);

        auto rng2 = JSONLexerRange!(string, options|LexOptions.noThrow)(str);
        assertNotThrown(rng2.front);
        assert(rng2.front.kind == JSONToken.Kind.error);
    }

    testFail("+");
    testFail("-");
    testFail("+1");
    testFail("1.");
    testFail(".1");
    testFail("01");
    testFail("1e");
    testFail("1e+");
    testFail("1e-");
    testFail("1.e");
    testFail("1.e-");
    testFail("1.ee");
    testFail("1.e-e");
    testFail("1.e+e");
    testFail("NaN");
    testFail("Infinity");
    testFail("-Infinity");
    testFail!(LexOptions.specialFloatLiterals)("NaX");
    testFail!(LexOptions.specialFloatLiterals)("InfinitX");
    testFail!(LexOptions.specialFloatLiterals)("-InfinitX");
}


/**
 * A low-level JSON token as returned by $(D JSONLexer).
*/
struct JSONToken
{
    @safe:
    import std.algorithm : among;

    /**
     * The kind of token represented.
     */
    enum Kind
    {
        none,         /// Used internally, never returned from the lexer
        error,        /// Malformed token
        null_,        /// The "null" token
        boolean,      /// "true" or "false" token
        number,       /// Numeric token
        string,       /// String token, stored in escaped form
        objectStart,  /// The "{" token
        objectEnd,    /// The "}" token
        arrayStart,   /// The "[" token
        arrayEnd,     /// The "]" token
        colon,        /// The ":" token
        comma         /// The "," token
    }

    private
    {
        union
        {
            JSONString _string;
            bool _boolean;
            JSONNumber _number;
        }
        Kind _kind = Kind.none;
    }

    /// The location of the token in the input.
    Location location;

    ref JSONToken opAssign(JSONToken other) nothrow @trusted
    {
        _kind = other._kind;
        final switch (_kind) with (Kind) {
            case none, error, null_, objectStart, objectEnd, arrayStart, arrayEnd, colon, comma:
                break;
            case boolean: _boolean = other._boolean; break;
            case number: _number = other._number; break;
            case string: _string = other._string; break;
        }

        this.location = other.location;
        return this;
    }

    /**
     * Gets/sets the kind of the represented token.
     *
     * Setting the token kind is not allowed for any of the kinds that have
     * additional data associated (boolean, number and string).
     */
    @property Kind kind() const nothrow { return _kind; }
    /// ditto
    @property Kind kind(Kind value) nothrow
        in { assert(!value.among(Kind.boolean, Kind.number, Kind.string)); }
        body { return _kind = value; }

    /// Gets/sets the boolean value of the token.
    @property bool boolean() const nothrow
    {
        assert(_kind == Kind.boolean, "Token is not a boolean.");
        return _boolean;
    }
    /// ditto
    @property bool boolean(bool value) nothrow
    {
        _kind = Kind.boolean;
        _boolean = value;
        return value;
    }

    /// Gets/sets the numeric value of the token.
    @property JSONNumber number() const nothrow @trusted
    {
        assert(_kind == Kind.number, "Token is not a number.");
        return _number;
    }
    /// ditto
    @property JSONNumber number(JSONNumber value) nothrow @trusted
    {
        _kind = Kind.number;
        _number = value;
        return value;
    }
    /// ditto
    @property JSONNumber number(double value) nothrow { return this.number = JSONNumber(value); }

    /// Gets/sets the string value of the token.
    @property JSONString string() const @trusted nothrow
    {
        assert(_kind == Kind.string, "Token is not a string.");
        return _string;
    }
    /// ditto
    @property JSONString string(JSONString value) nothrow
    {
        _kind = Kind.string;
        _string = value;
        return value;
    }
    /// ditto
    @property JSONString string(.string value) nothrow { return this.string = JSONString(value); }

    /**
     * Enables equality comparisons.
     *
     * Note that the location is considered token meta data and thus does not
     * affect the comparison.
     */
    bool opEquals(in ref JSONToken other) const nothrow
    {
        if (this.kind != other.kind) return false;

        switch (this.kind)
        {
            default: return true;
            case Kind.boolean: return this.boolean == other.boolean;
            case Kind.number: return this.number == other.number;
            case Kind.string: return this.string == other.string;
        }
    }
    /// ditto
    bool opEquals(JSONToken other) const nothrow { return opEquals(other); }

    /**
     * Enables usage of $(D JSONToken) as an associative array key.
     */
    size_t toHash() const nothrow
    {
        hash_t ret = 3781249591u + cast(uint)_kind * 2721371;

        switch (_kind)
        {
            default: return ret;
            case Kind.boolean: return ret + _boolean;
            case Kind.number: return ret + typeid(double).getHash(&_number);
            case Kind.string: return ret + typeid(.string).getHash(&_string);
        }
    }

    /**
     * Converts the token to a string representation.
     *
     * Note that this representation is NOT the JSON representation, but rather
     * a representation suitable for printing out a token including its
     * location.
     */
    .string toString() const @trusted
    {
        import std.string;
        switch (this.kind)
        {
            default: return format("[%s %s]", location, this.kind);
            case Kind.boolean: return format("[%s %s]", location, this.boolean);
            case Kind.number: return format("[%s %s]", location, this.number);
            case Kind.string: return format("[%s \"%s\"]", location, this.string);
        }
    }
}

unittest
{
    JSONToken tok;

    assert((tok.boolean = true) == true);
    assert(tok.kind == JSONToken.Kind.boolean);
    assert(tok.boolean == true);

    assert((tok.number = 1.0) == 1.0);
    assert(tok.kind == JSONToken.Kind.number);
    assert(tok.number == 1.0);

    assert((tok.string = "test") == "test");
    assert(tok.kind == JSONToken.Kind.string);
    assert(tok.string == "test");

    assert((tok.kind = JSONToken.Kind.none) == JSONToken.Kind.none);
    assert(tok.kind == JSONToken.Kind.none);
    assert((tok.kind = JSONToken.Kind.error) == JSONToken.Kind.error);
    assert(tok.kind == JSONToken.Kind.error);
    assert((tok.kind = JSONToken.Kind.null_) == JSONToken.Kind.null_);
    assert(tok.kind == JSONToken.Kind.null_);
    assert((tok.kind = JSONToken.Kind.objectStart) == JSONToken.Kind.objectStart);
    assert(tok.kind == JSONToken.Kind.objectStart);
    assert((tok.kind = JSONToken.Kind.objectEnd) == JSONToken.Kind.objectEnd);
    assert(tok.kind == JSONToken.Kind.objectEnd);
    assert((tok.kind = JSONToken.Kind.arrayStart) == JSONToken.Kind.arrayStart);
    assert(tok.kind == JSONToken.Kind.arrayStart);
    assert((tok.kind = JSONToken.Kind.arrayEnd) == JSONToken.Kind.arrayEnd);
    assert(tok.kind == JSONToken.Kind.arrayEnd);
    assert((tok.kind = JSONToken.Kind.colon) == JSONToken.Kind.colon);
    assert(tok.kind == JSONToken.Kind.colon);
    assert((tok.kind = JSONToken.Kind.comma) == JSONToken.Kind.comma);
    assert(tok.kind == JSONToken.Kind.comma);
}


/**
 * Represents a JSON string literal with lazy (un)escaping.
 */
struct JSONString {
    private {
        string _value;
        string _rawValue;
    }

    nothrow:

    /**
     * Constructs a JSONString from the given string value (unescaped).
     */
    this(string value)
    {
        _value = value;
    }

    /**
     * The decoded (unescaped) string value.
     */
    @property string value()
    {
        if (!_value.length && _rawValue.length) {
            auto res = unescapeStringLiteral(_rawValue, _value);
            assert(res, "Invalid raw string literal passed to JSONString: "~_rawValue);
        }
        return _value;
    }
    /// ditto
    @property string value() const
    {
        if (!_value.length && _rawValue.length) {
            string unescaped;
            auto res = unescapeStringLiteral(_rawValue, unescaped);
            assert(res, "Invalid raw string literal passed to JSONString: "~_rawValue);
            return unescaped;
        }
        return _value;
    }
    /// ditto
    @property string value(string val)
    {
        _rawValue = null;
        return _value = val;
    }

    /**
     * The raw (escaped) string literal, including the enclosing quotation marks.
     */
    @property string rawValue()
    {
        if (!_rawValue.length && _value.length)
            _rawValue = escapeStringLiteral(_value);
        return _rawValue;
    }
    /// ditto
    @property string rawValue(string val)
    {
        assert(isValidStringLiteral(val), "Invalid raw string literal: "~val);
        _rawValue = val;
        _value = null;
        return val;
    }

    alias value this;

    /// Support equality comparisons
    bool opEquals(JSONString other) nothrow { return value == other.value; }
    /// ditto
    bool opEquals(JSONString other) const nothrow { return this.value == other.value; }
    /// ditto
    bool opEquals(string other) nothrow { return this.value == other; }
    /// ditto
    bool opEquals(string other) const nothrow { return this.value == other; }

    /// Support relational comparisons
    int opCmp(JSONString other) nothrow @trusted { import std.algorithm; return cmp(this.value, other.value); }

    /// Support use as hash key
    size_t toHash() const nothrow @trusted { auto val = this.value; return typeid(string).getHash(&val); }
}

unittest {
    JSONString s = "test";
    assert(s == "test");
    assert(s.value == "test");
    assert(s.rawValue == `"test"`);

    JSONString t;
    auto h = `"hello"`;
    s.rawValue = h;
    t = s; assert(s == t);
    assert(s.rawValue == h);
    assert(s.value == "hello");
    t = s; assert(s == t);
    assert(&s.rawValue[0] is &h[0]);
    assert(&s.value[0] is &h[1]);

    auto w = `"world\t!"`;
    s.rawValue = w;
    t = s; assert(s == t);
    assert(s.rawValue == w);
    assert(s.value == "world\t!");
    t = s; assert(s == t);
    assert(&s.rawValue[0] is &w[0]);
    assert(&s.value[0] !is &h[1]);
}


/**
 * Represents a JSON number literal with lazy conversion.
 */
struct JSONNumber {
    import std.bigint;

    enum Type {
        double_,
        long_,
        bigInt/*,
        decimal*/
    }

    private struct Decimal {
        BigInt integer;
        int exponent;
    }

    private {
        union {
            double _double;
            long _long;
            Decimal _decimal;
        }
        Type _type = Type.long_;
    }

    /**
     * Constructs a $(D JSONNumber) from a raw number.
     */
    this(double value) nothrow { this.doubleValue = value; }
    /// ditto
    this(long value) nothrow { this.longValue = value; }
    /// ditto
    this(BigInt value) nothrow { this.bigIntValue = value; }
    // ditto
    //this(Decimal value) nothrow { this.decimalValue = value; }

    /**
     * The native type of the stored number.
     */
    @property Type type() const { return _type; }

    /**
     * Returns the number as a $(D double) value.
     *
     * Regardless of the current type of this number, this property will always
     * yield a value converted to $(D double). Setting this property will
     * automatically update the number type to $(D Type.double_).
     */
    @property double doubleValue() const nothrow @trusted
    {
        final switch (_type)
        {
            case Type.double_: return _double;
            case Type.long_: return cast(double)_long;
            case Type.bigInt: try return cast(double)_decimal.integer.toLong(); catch(Exception) assert(false); // FIXME: directly convert to double
            //case Type.decimal: try return cast(double)_decimal.integer.toLong() * 10.0 ^^ _decimal.exponent; catch(Exception) assert(false); // FIXME: directly convert to double
        }
    }
    /// ditto
    @property double doubleValue(double value) nothrow
    {
        _type = Type.double_;
        return _double = value;
    }

    /**
     * Returns the number as a $(D long) value.
     *
     * Regardless of the current type of this number, this property will always
     * yield a value converted to $(D long). Setting this property will
     * automatically update the number type to $(D Type.long_).
     */
    @property long longValue() const nothrow @trusted
    {
        import std.math;

        final switch (_type)
        {
            case Type.double_: return rndtol(_double);
            case Type.long_: return _long;
            case Type.bigInt: try return _decimal.integer.toLong(); catch(Exception) assert(false);
            /*case Type.decimal:
                try
                {
                    if (_decimal.exponent == 0) return _decimal.integer.toLong();
                    else if (_decimal.exponent > 0) return (_decimal.integer * BigInt(10) ^^ _decimal.exponent).toLong();
                    else return (_decimal.integer / BigInt(10) ^^ -_decimal.exponent).toLong();
                }
                catch(Exception) assert(false);*/
        }
    }
    /// ditto
    @property long longValue(long value) nothrow
    {
        _type = Type.long_;
        return _long = value;
    }

    /**
     * Returns the number as a $(D BigInt) value.
     *
     * Regardless of the current type of this number, this property will always
     * yield a value converted to $(D BigInt). Setting this property will
     * automatically update the number type to $(D Type.bigInt).
     */
    @property BigInt bigIntValue() const nothrow @trusted
    {
        import std.math;

        final switch (_type)
        {
            case Type.double_: return BigInt(rndtol(_double)); // FIXME: convert to string and then to bigint
            case Type.long_: return BigInt(_long);
            case Type.bigInt: return _decimal.integer;
            /*case Type.decimal:
                try
                {
                    if (_decimal.exponent == 0) return _decimal.integer;
                    else if (_decimal.exponent > 0) return _decimal.integer * BigInt(10) ^^ _decimal.exponent;
                    else return _decimal.integer / BigInt(10) ^^ -_decimal.exponent;
                }
                catch (Exception) assert(false);*/
        }
    }
    /// ditto
    @property BigInt bigIntValue(BigInt value) nothrow @trusted
    {
        _type = Type.bigInt;
        _decimal.exponent = 0;
        return _decimal.integer = value;
    }

    /+/**
     * Returns the number as a $(D Decimal) value.
     *
     * Regardless of the current type of this number, this property will always
     * yield a value converted to $(D Decimal). Setting this property will
     * automatically update the number type to $(D Type.decimal).
     */
    @property Decimal decimalValue() const nothrow @trusted
    {
        import std.bitmanip;
        import std.math;

        final switch (_type)
        {
            case Type.double_:
                Decimal ret;
                assert(false, "TODO");
            case Type.long_: return Decimal(BigInt(_long), 0);
            case Type.bigInt: return Decimal(_decimal.integer, 0);
            case Type.decimal: return _decimal;
        }
    }
    /// ditto
    @property Decimal decimalValue(Decimal value) nothrow @trusted
    {
        _type = Type.decimal;
        try return _decimal = value;
        catch (Exception) assert(false);
    }+/

    /// Makes a JSONNumber behave like a $(D double) by default.
    alias doubleValue this;

    /**
     * Support assignment of numbers.
     */
    void opAssign(JSONNumber other) nothrow @trusted
    {
        _type = other._type;
        final switch (_type) {
            case Type.double_: _double = other._double; break;
            case Type.long_: _long = other._long; break;
            case Type.bigInt/*, Type.decimal*/:
                try _decimal = other._decimal;
                catch (Exception) assert(false);
                break;
        }
    }
    /// ditto
    void opAssign(double value) { this.doubleValue = value; }
    /// ditto
    void opAssign(long value) { this.longValue = value; }
    /// ditto
    void opAssign(BigInt value) { this.bigIntValue = value; }
    // ditto
    //void opAssign(Decimal value) { this.decimalValue = value; }

    /// Support equality comparisons
    bool opEquals(T)(T other) const nothrow
    {
        static if (is(T == JSONNumber)) return _double == other._double;
        else static if (is(T : double)) return _double == other;
        else static assert(false, "Unsupported type for comparison: "~T.stringof);
    }

    /// Support relational comparisons
    int opCmp(T)(T other) const nothrow
    {
        static if (is(T == JSONNumber)) return this == other._double;
        else static if (is(T : double)) return _double < other ? -1 : _double > other ? 1 : 0;
        else static assert(false, "Unsupported type for comparison: "~T.stringof);

    }

    /// Support use as hash key
    size_t toHash() const nothrow @trusted
    {
        auto val = this.doubleValue;
        return typeid(double).getHash(&val);
    }
}

unittest // assignment operator
{
    import std.bigint;

    JSONNumber num, num2;

    num = 1.0;
    assert(num.type == JSONNumber.Type.double_);
    assert(num == 1.0);
    num2 = num;
    assert(num2.type == JSONNumber.Type.double_);
    assert(num2 == 1.0);

    num = 1L;
    assert(num.type == JSONNumber.Type.long_);
    assert(num.longValue == 1);
    num2 = num;
    assert(num2.type == JSONNumber.Type.long_);
    assert(num2.longValue == 1);

    num = BigInt(1);
    assert(num.type == JSONNumber.Type.bigInt);
    assert(num.bigIntValue == 1);
    num2 = num;
    assert(num2.type == JSONNumber.Type.bigInt);
    assert(num2.bigIntValue == 1);

    /*num = JSONNumber.Decimal(BigInt(1), 0);
    assert(num.type == JSONNumber.Type.decimal);
    assert(num.decimalValue == JSONNumber.Decimal(BigInt(1), 0));
    num2 = num;
    assert(num2.type == JSONNumber.Type.decimal);
    assert(num2.decimalValue == JSONNumber.Decimal(BigInt(1), 0));*/
}

unittest // property access
{
    import std.bigint;

    JSONNumber num;

    num.longValue = 2;
    assert(num.type == JSONNumber.Type.long_);
    assert(num.longValue == 2);
    assert(num.doubleValue == 2.0);
    assert(num.bigIntValue == 2);
    //assert(num.decimalValue.integer == 2 && num.decimalValue.exponent == 0);

    num.doubleValue = 2.0;
    assert(num.type == JSONNumber.Type.double_);
    assert(num.longValue == 2);
    assert(num.doubleValue == 2.0);
    assert(num.bigIntValue == 2);
    //assert(num.decimalValue.integer == 2 * 10 ^^ -num.decimalValue.exponent);

    num.bigIntValue = BigInt(2);
    assert(num.type == JSONNumber.Type.bigInt);
    assert(num.longValue == 2);
    assert(num.doubleValue == 2.0);
    assert(num.bigIntValue == 2);
    //assert(num.decimalValue.integer == 2 && num.decimalValue.exponent == 0);

    /*num.decimalValue = JSONNumber.Decimal(BigInt(2), 0);
    assert(num.type == JSONNumber.Type.decimal);
    assert(num.longValue == 2);
    assert(num.doubleValue == 2.0);
    assert(num.bigIntValue == 2);
    assert(num.decimalValue.integer == 2 && num.decimalValue.exponent == 0);*/
}

unittest // negative numbers
{
    import std.bigint;

    JSONNumber num;

    num.longValue = -2;
    assert(num.type == JSONNumber.Type.long_);
    assert(num.longValue == -2);
    assert(num.doubleValue == -2.0);
    assert(num.bigIntValue == -2);
    //assert(num.decimalValue.integer == -2 && num.decimalValue.exponent == 0);

    num.doubleValue = -2.0;
    assert(num.type == JSONNumber.Type.double_);
    assert(num.longValue == -2);
    assert(num.doubleValue == -2.0);
    assert(num.bigIntValue == -2);
    //assert(num.decimalValue.integer == -2 && num.decimalValue.exponent == 0);

    num.bigIntValue = BigInt(-2);
    assert(num.type == JSONNumber.Type.bigInt);
    assert(num.longValue == -2);
    assert(num.doubleValue == -2.0);
    assert(num.bigIntValue == -2);
    //assert(num.decimalValue.integer == -2 && num.decimalValue.exponent == 0);

    /*num.decimalValue = JSONNumber.Decimal(BigInt(-2), 0);
    assert(num.type == JSONNumber.Type.decimal);
    assert(num.longValue == -2);
    assert(num.doubleValue == -2.0);
    assert(num.bigIntValue == -2);
    assert(num.decimalValue.integer == -2 && num.decimalValue.exponent == 0);*/
}


/**
 * Flags for configuring the JSON lexer.
 *
 * These flags can be combined using a bitwise or operation.
 */
enum LexOptions {
    init            = 0,    /// Default options - track token location and only use double to represent numbers
    noTrackLocation = 1<<0, /// Counts lines and columns while lexing the source
    noThrow         = 1<<1, /// Uses JSONToken.Kind.error instead of throwing exceptions
    useLong         = 1<<2, /// Use long to represent integers
    useBigInt       = 1<<3, /// Use BigInt to represent integers (if larger than long or useLong is not given)
    //useDecimal      = 1<<4, /// Use Decimal to represent floating point numbers
    specialFloatLiterals = 1<<5, /// Support "NaN", "Infinite" and "-Infinite" as valid number literals
}


package enum bool isStringInputRange(R) = isInputRange!R && isSomeChar!(typeof(R.init.front));
package enum bool isIntegralInputRange(R) = isInputRange!R && isIntegral!(typeof(R.init.front));

// returns true for success
package bool unescapeStringLiteral(bool track_location, bool skip_utf_validation, Input, Output)(
    ref Input input, // input range, string and immutable(ubyte)[] can be sliced
    ref Output output, // uninitialized output range
    ref string sliced_result, // target for possible result slice
    scope void delegate() @safe nothrow output_init, // delegate that is called before writing to output
    ref string error, // target for error message
    ref size_t column) // counter to use for tracking the current column
{
    static if (typeof(Input.init.front).sizeof > 1)
        alias CharType = dchar;
    else
        alias CharType = char;

    import std.algorithm : skipOver;
    import std.array;

    if (input.empty || input.front != '"')
    {
        error = "String literal must start with double quotation mark";
        return false;
    }

    input.popFront();
    static if (track_location) column++;

    // try the fast slice based route first
    static if (is(Input == string) || is(Input == immutable(ubyte)[]))
    {
        auto orig = input;
        size_t idx = 0;
        while (true)
        {
            if (idx >= input.length)
            {
                error = "Unterminated string literal";
                return false;
            }

            // return a slice for simple strings
            if (input[idx] == '"')
            {
                input = input[idx+1 .. $];
                static if (track_location) column += idx+1;
                sliced_result = cast(string)orig[0 .. idx];

                static if (!skip_utf_validation)
                {
                    import std.encoding;
                    if (!isValid(sliced_result))
                    {
                        error = "Invalid UTF sequence in string literal";
                        return false;
                    }
                }

                return true;
            }

            // fall back to full decoding when an escape sequence is encountered
            if (input[idx] == '\\')
            {
                output_init();
                static if (!skip_utf_validation)
                {
                    if (!isValid(input[0 .. idx]))
                    {
                        error = "Invalid UTF sequence in string literal";
                        return false;
                    }
                }
                output.put(cast(string)input[0 .. idx]);
                input = input[idx .. $];
                static if (track_location) column += idx;
                break;
            }

            // Make sure that no illegal characters are present
            if (input[idx] < 0x20)
            {
                error = "Control chararacter found in string literal";
                return false;
            }
            idx++;
        }
    } else output_init();

    // perform full decoding
    while (true)
    {
        if (input.empty)
        {
            error = "Unterminated string literal";
            return false;
        }

        static if (!skip_utf_validation)
        {
            import std.utf;
            dchar ch;
            size_t numcu;
            auto chrange = castRange!CharType(input);
            try ch = ()@trusted{ return decodeFront(chrange); }();
            catch (UTFException)
            {
                error = "Invalid UTF sequence in string literal";
                return false;
            }
            if (!isValidDchar(ch))
            {
                error = "Invalid Unicode character in string literal";
                return false;
            }
            static if (track_location) column += numcu;
        }
        else
        {
            auto ch = input.front;
            input.popFront();
            static if (track_location) column++;
        }

        switch (ch)
        {
            default:
                output.put(cast(CharType)ch);
                break;
            case 0x00: .. case 0x19:
                error = "Illegal control character in string literal";
                return false;
            case '"': return true;
            case '\\':
                if (input.empty)
                {
                    error = "Unterminated string escape sequence.";
                    return false;
                }

                auto ech = input.front;
                input.popFront();
                static if (track_location) column++;

                switch (ech)
                {
                    default:
                        error = "Invalid string escape sequence.";
                        return false;
                    case '"': output.put('\"'); break;
                    case '\\': output.put('\\'); break;
                    case '/': output.put('/'); break;
                    case 'b': output.put('\b'); break;
                    case 'f': output.put('\f'); break;
                    case 'n': output.put('\n'); break;
                    case 'r': output.put('\r'); break;
                    case 't': output.put('\t'); break;
                    case 'u': // \uXXXX
                        dchar uch = decodeUTF16CP(input, error);
                        if (uch == dchar.max) return false;
                        static if (track_location) column += 4;

                        // detect UTF-16 surrogate pairs
                        if (0xD800 <= uch && uch <= 0xDBFF)
                        {
                            static if (track_location) column += 6;

                            if (!input.skipOver("\\u"))
                            {
                                error = "Missing second UTF-16 surrogate";
                                return false;
                            }

                            auto uch2 = decodeUTF16CP(input, error);
                            if (uch2 == dchar.max) return false;

                            if (0xDC00 > uch2 || uch2 > 0xDFFF)
                            {
                                error = "Invalid UTF-16 surrogate sequence";
                                return false;
                            }

                            // combine to a valid UCS-4 character
                            uch = ((uch - 0xD800) << 10) + (uch2 - 0xDC00) + 0x10000;
                        }

                        output.put(uch);
                        break;
                }
                break;
        }
    }
}

package bool unescapeStringLiteral(string str_lit, ref string dst)
nothrow {
    import std.string;

    bool appender_init = false;
    Appender!string app;
    string slice, error;
    size_t col;

    void initAppender() @safe nothrow { app = appender!string(); appender_init = true; }

    auto rep = str_lit.representation;
    try // Appender.put and skipOver are not nothrow
    {
        if (!unescapeStringLiteral!(false, true)(rep, app, slice, &initAppender, error, col))
            return false;
    }
    catch (Exception e) return false;

    dst = appender_init ? app.data : slice;
    return true;
}

package bool isValidStringLiteral(string str)
nothrow {
    string dst;
    return unescapeStringLiteral(str, dst);
}


package bool skipStringLiteral(bool track_location = true, Array)(
        ref Array input,
        ref Array destination,
        ref string error, // target for error message
        ref size_t column // counter to use for tracking the current column
    )
{
    import std.algorithm : skipOver;
    import std.array;

    if (input.empty || input.front != '"')
    {
        error = "String literal must start with double quotation mark";
        return false;
    }

    destination = input;

    input.popFront();

    while (true)
    {
        if (input.empty)
        {
            error = "Unterminated string literal";
            return false;
        }

        auto ch = input.front;
        input.popFront();

        switch (ch)
        {
            default: break;
            case 0x00: .. case 0x19:
                error = "Illegal control character in string literal";
                return false;
            case '"':
                size_t len = destination.length - input.length;
                static if (track_location) column += len;
                destination = destination[0 .. len];
                return true;
            case '\\':
                if (input.empty)
                {
                    error = "Unterminated string escape sequence.";
                    return false;
                }

                auto ech = input.front;
                input.popFront();

                switch (ech)
                {
                    default:
                        error = "Invalid string escape sequence.";
                        return false;
                    case '"', '\\', '/', 'b', 'f', 'n', 'r', 't': break;
                    case 'u': // \uXXXX
                        dchar uch = decodeUTF16CP(input, error);
                        if (uch == dchar.max) return false;

                        // detect UTF-16 surrogate pairs
                        if (0xD800 <= uch && uch <= 0xDBFF)
                        {
                            if (!input.skipOver("\\u"))
                            {
                                error = "Missing second UTF-16 surrogate";
                                return false;
                            }

                            auto uch2 = decodeUTF16CP(input, error);
                            if (uch2 == dchar.max) return false;

                            if (0xDC00 > uch2 || uch2 > 0xDFFF)
                            {
                                error = "Invalid UTF-16 surrogate sequence";
                                return false;
                            }
                        }
                        break;
                }
                break;
        }
    }
}


package void escapeStringLiteral(bool use_surrogates = false, Input, Output)(
    ref Input input, // input range containing the string
    ref Output output) // output range to hold the escaped result
{
    import std.format;
    import std.utf : decode;

    output.put('"');

    while (!input.empty)
    {
        immutable ch = input.front;
        input.popFront();

        switch (ch)
        {
            case '\\': output.put(`\\`); break;
            case '\b': output.put(`\b`); break;
            case '\f': output.put(`\f`); break;
            case '\r': output.put(`\r`); break;
            case '\n': output.put(`\n`); break;
            case '\t': output.put(`\t`); break;
            case '\"': output.put(`\"`); break;
            default:
                static if (use_surrogates)
                {
                    if (ch >= 0x20 && ch < 0x80)
                    {
                        output.put(ch);
                        break;
                    }

                    dchar cp = decode(s, pos);
                    pos--; // account for the next loop increment

                    // encode as one or two UTF-16 code points
                    if (cp < 0x10000)
                    { // in BMP -> 1 CP
                        formattedWrite(output, "\\u%04X", cp);
                    }
                    else
                    { // not in BMP -> surrogate pair
                        int first, last;
                        cp -= 0x10000;
                        first = 0xD800 | ((cp & 0xffc00) >> 10);
                        last = 0xDC00 | (cp & 0x003ff);
                        formattedWrite(output, "\\u%04X\\u%04X", first, last);
                    }
                }
                else
                {
                    if (ch < 0x20) formattedWrite(output, "\\u%04X", ch);
                    else output.put(ch);
                }
                break;
        }
    }

    output.put('"');
}

package string escapeStringLiteral(string str)
nothrow {
    import std.string;

    auto rep = str.representation;
    auto ret = appender!string();
    try // Appender.put is not nothrow
    {
        escapeStringLiteral(rep, ret);
    }
    catch (Exception e) assert(false);
    return ret.data;
}

private dchar decodeUTF16CP(R)(ref R input, ref string error)
{
    dchar uch = 0;
    foreach (i; 0 .. 4)
    {
        if (input.empty)
        {
            error = "Premature end of unicode escape sequence";
            return dchar.max;
        }

        uch *= 16;
        auto dc = input.front;
        input.popFront();

        if (dc >= '0' && dc <= '9')
            uch += dc - '0';
        else if ((dc >= 'a' && dc <= 'f') || (dc >= 'A' && dc <= 'F'))
            uch += (dc & ~0x20) - 'A' + 10;
        else
        {
            error = "Invalid character in Unicode escape sequence";
            return dchar.max;
        }
    }
    return uch;
}

// little helper to be able to pass integer ranges to std.utf.decodeFront
private struct CastRange(T, R)
{
    private R* _range;

    this(R* range) { _range = range; }
    @property bool empty() { return (*_range).empty; }
    @property T front() { return cast(T)(*_range).front; }
    void popFront() { (*_range).popFront(); }
}
private CastRange!(T, R) castRange(T, R)(ref R range) @trusted { return CastRange!(T, R)(&range); }
static assert(isInputRange!(CastRange!(char, uint[])));
