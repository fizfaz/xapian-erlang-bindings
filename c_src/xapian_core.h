#ifndef XAPIAN_CORE_H
#define XAPIAN_CORE_H

#include "result_encoder.h"
#include "qlc_table.h"
#include "object_register.h"
#include "user_resources.h"
#include <xapian.h>
#include <string>
#include <cstring>
#include <stdint.h>

#include "erl_driver.h"
/* Hack to handle R15 driver used with pre R15 driver */
#if ERL_DRV_EXTENDED_MAJOR_VERSION == 1
typedef int  ErlDrvSizeT;
typedef int  ErlDrvSSizeT;
#endif

// -------------------------------------------------------------------
// Main Driver Class
// -------------------------------------------------------------------

class XapianErlangDriver 
{
    Xapian::Database* mp_db;
    Xapian::WritableDatabase* mp_wdb;
    const Xapian::Stem* mp_default_stemmer;

    ResultEncoder m_result;
    Xapian::QueryParser m_default_parser;
    Xapian::QueryParser m_empty_parser;
    ObjectRegister<Xapian::Enquire> m_enquire_store;
    ObjectRegister<Xapian::MSet>    m_mset_store;
    ObjectRegister<const QlcTable>  m_qlc_store;

    /**
     * It is global.
     * It knows how to create user customized resources.
     */
    ResourceGenerator&  m_generator;

    /**
     * It is different for each port.
     * It is a manager of ObjectRegisters.
     */
    ResourceManager     m_stores;

    public:
    friend class MSetQlcTable;

    // Commands
    // used in the control function
    enum command {
        OPEN                        = 0,
        LAST_DOC_ID                 = 1,
        ADD_DOCUMENT                = 2,
        TEST                        = 3,
        GET_DOCUMENT_BY_ID          = 4,
        START_TRANSACTION           = 5,
        CANCEL_TRANSACTION          = 6,
        COMMIT_TRANSACTION          = 7,
        QUERY_PAGE                  = 8,
        SET_DEFAULT_STEMMER         = 9,
        SET_DEFAULT_PREFIXES        = 10,
        ENQUIRE                     = 11,
        RELEASE_RESOURCE            = 12,
        MATCH_SET                   = 13,
        QLC_INIT                    = 14,
        QLC_NEXT_PORTION            = 15,
        QLC_LOOKUP                  = 16
    };

    // Error prefix tags.
    // used in the control function
    enum errorCode {
        SUCCESS                     = 0,
        ERROR                       = 1
    };

    // Modes for opening of a db
    // used in the open function
    enum openMode {
        READ_OPEN                   = 0,
        WRITE_CREATE_OR_OPEN        = 1,
        WRITE_CREATE                = 2,
        WRITE_CREATE_OR_OVERWRITE   = 3,
        WRITE_OPEN                  = 4
    };

    // Types of fields
    // Used in the applyDocument function.
    enum fieldTypeIn {
        STEMMER                     = 1,
        DATA                        = 2,
        VALUE                       = 3,
        DELTA                       = 4,
        TEXT                        = 5,
        TERM                        = 6,
        POSTING                     = 7
    };

    // Types of the fields.
    // Used in the retrieveDocument function.
    enum fieldTypeOut {
        GET_VALUE                   = 1,
        GET_DATA                    = 2,
        GET_DOCID                   = 3,
        GET_WEIGHT                  = 4,
        GET_RANK                    = 5,
        GET_PERCENT                 = 6
    };

    // Numbers of tests.
    // Used in the test function.
    enum testNumber {
        TEST_RESULT_ENCODER         = 1,
        TEST_EXCEPTION              = 2
    };

    enum queryType {
        QUERY_GROUP                 = 1,
        QUERY_VALUE                 = 2,
        QUERY_VALUE_RANGE           = 3,
        QUERY_TERM                  = 4,
        QUERY_PARSER                = 5
    };

    enum queryParserCommand {
        QP_STEMMER                  = 1,
        QP_STEMMING_STRATEGY        = 2,
        QP_MAX_WILDCARD_EXPANSION   = 3,
        QP_DEFAULT_OP               = 4,
        QP_PARSER_TYPE              = 5,
        QP_PREFIX                   = 6
    };

    enum queryParserType {
        QP_TYPE_DEFAULT             = 0,
        QP_TYPE_EMPTY               = 1
    };

    enum resourceType {
        ENQUIRE_RESOURCE_TYPE       = 0,
        MSET_RESOURCE_TYPE          = 1,
        QLC_RESOURCE_TYPE           = 2
    };


    /* see xapian_enquire:encode */
    enum enquireCommand {
        EC_STOP             = 0,
        EC_QUERY            = 1,
        EC_QUERY_LEN        = 2,
        EC_ORDER            = 3,
        EC_DOCID_ORDER      = 4,
        EC_WEIGHTING_SCHEME = 5,
        EC_CUTOFF           = 6,
        EC_COLLAPSE_KEY     = 7
    };

    enum enquireOrderTypes {
        OT_KEY              = 1,
        OT_VALUE            = 2,
        OT_KEY_RELEVANCE    = 3,
        OT_RELEVANCE_KEY    = 4,
        OT_RELEVANCE_VALUE  = 5,
        OT_VALUE_RELEVANCE  = 6
    };

    static const unsigned
    PARSER_FEATURES[];

    static const uint8_t
    PARSER_FEATURE_COUNT;

    static const uint8_t
    STEM_STRATEGY_COUNT;

    static const Xapian::QueryParser::stem_strategy
    STEM_STRATEGIES[];

    static const uint8_t
    DOCID_ORDER_TYPE_COUNT;

    static const Xapian::Enquire::docid_order
    DOCID_ORDER_TYPES[];


    /**
     * The driver is loaded.
     * This is called only once.
     */
    static int 
    init();

    /**
     * The driver is unloaded.
     * This is called only once.
     */
    static void
    finish();

    /**
     * Here we do some initialization, start is called from open_port. 
     * The drv_data will be passed to control and stop.
     * This is called multiple times.
     */
    static ErlDrvData 
    start(ErlDrvPort port, char* /* buf */);

    /**
     * This is called multiple times.
     */
    static void 
    stop(ErlDrvData drv_data);

    static ErlDrvSSizeT control(
        ErlDrvData      drv_data, 
        unsigned int    command, 
        char*           buf, 
        ErlDrvSizeT     len, 
        char**          rbuf, 
        ErlDrvSizeT     rlen);

    ResultEncoder* getResultEncoder();

    /**
     * A constructor
     */
    XapianErlangDriver(ResourceGenerator&);

    ~XapianErlangDriver();

    void setDefaultStemmer(const Xapian::Stem* stemmer);

    size_t setDefaultStemmer(ParamDecoder& params);

    size_t setDefaultPrefixes(ParamDecoder& params);

    ObjectBaseRegister&
    getRegisterByType(uint8_t type);

    size_t open(const std::string& dbpath, int8_t mode);

    size_t getLastDocId();

    size_t addDocument(ParamDecoder& params);

    /**
     * Read commands, encoded by xapian_document:encode.
     * Used in update, replace, add document functions
     */
    void applyDocument(ParamDecoder& params, Xapian::Document& doc);

    /**
     * query_page
     */
    size_t query(ParamDecoder& params);

    /**
     * Return a resource 
     */
    size_t enquire(ParamDecoder& params);

    /**
     * Erase stored object
     */
    size_t releaseResource(ParamDecoder& params);

    /**
     * Converts an enquire into a match set
     */
    size_t matchSet(ParamDecoder& params);

    size_t qlcInit(ParamDecoder& params);

    size_t qlcNext(ParamDecoder& params);

    size_t qlcLookup(ParamDecoder& params);

    /** 
     * Gets a copy of params.
     *
     * `params' is a clone.
     */
    void retrieveDocument(ParamDecoder, Xapian::Document&, Xapian::MSetIterator*);

    ParamDecoderController
    retrieveDocumentSchema(ParamDecoder&) const;

    Xapian::Query 
    buildQuery(ParamDecoder& params);

    void fillEnquire(Xapian::Enquire& enquire, ParamDecoder& params);

    void fillEnquireOrder(Xapian::Enquire& enquire, 
        const uint8_t type, const uint32_t value, const bool reverse);

    /**
     * Throws error if the database was opened only for reading.
     */
    void assertWriteable() const;

    size_t startTransaction();

    size_t cancelTransaction();

    size_t commitTransaction();

    size_t getDocumentById(ParamDecoder& params);

    size_t test(ParamDecoder& params);

    size_t testResultEncoder(Xapian::docid from, Xapian::docid to);

    size_t testException();

    static unsigned
    idToParserFeature(uint8_t type);

    static unsigned 
    decodeParserFeatureFlags(ParamDecoder& params);

    static Xapian::QueryParser::stem_strategy
    readStemmingStrategy(ParamDecoder& params);

    Xapian::QueryParser
    readParser(ParamDecoder& params);

    Xapian::QueryParser 
    selectParser(ParamDecoder& params);

    void addPrefix(Xapian::QueryParser& qp, ParamDecoder& params);
};

#endif