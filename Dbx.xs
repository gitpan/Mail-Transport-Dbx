#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "libdbx/libdbx.h"
#include "libdbx/timeconv.h"

#include "const-c.inc"

/* This is not gentlemen-like:
 * But under Win32: (PerlIO*) == (FILE*) */
#ifdef _WIN32
# define PerlIO_exportFILE(f,fl) ((FILE*)(f))
#endif

#define glob_ref(sv) (SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVGV)
#define sv_to_file(sv) (PerlIO_exportFILE(IoIFP(sv_2io(sv)), NULL))

struct dbx_email {
    DBX         *dbx;
    DBXEMAIL    *email;
    char        *header;  /* just the header */
    char        *body;    /* just the body */
};

struct dbx_folder {
    DBX         *dbx;
    DBXFOLDER   *folder;
};

typedef struct dbx_email    DBX_EMAIL;
typedef struct dbx_folder   DBX_FOLDER;

/* copied from perl/pp_sys.c */
static char *dayname[] = {
    "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
};
static char *monname[] = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", 
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

char * errstr () {
        switch(dbx_errno) {
            /* messages copied from libdbx.h */
            case DBX_NOERROR:
                return "No error";
            case DBX_BADFILE:
                return "Dbx file operation failed (open or close)";
            case DBX_ITEMCOUNT:
                return "Reading of Item Count from dbx file failed";
            case DBX_INDEX_READ:
                return "Reading of Index Pointer from dbx file failed";
            case DBX_INDEX_UNDERREAD:
                return 
                "Number of indexes read from dbx file is less than expected";
            case DBX_INDEX_OVERREAD:
                return
                "Request was made for index reference greater than exists";
            case DBX_INDEXCOUNT:
                return "Index out of range";
            case DBX_DATA_READ:
                return "Reading of data from dbx file failed";
            case DBX_NEWS_ITEM:
                return "Item is a news item not an email";
            default:
                break;
        }
        return "Odd...an unknown error occured";
}

void split_mail (pTHX_ DBX_EMAIL *self) {

    if (self->header)
        return;
    
    else {
        char *ptr;
        int count = 0;

        /* email data not yet loaded */
        if (!self->email->email) 
            (void) dbx_get_email_body(self->dbx, self->email);
        
        ptr = self->email->email;
        
        if (dbx_errno == DBX_DATA_READ) {
            /* A message can be there and not be there at the same time!
             * Explanation:
             * newsgroup items can be downloaded partially in OutlookX
             * In this case dbx_get_email_body() will store nothing in
             * self->email->email in which case header and body would be 
             * empty. then dbx_errno is set to DBX_DATA_READ which we
             * don't consider an error here */
            dbx_errno = DBX_NOERROR;
            return;
        }
        if (dbx_errno == DBX_BADFILE)
            croak("dbx panic: file stream disappeared");

        while (ptr+4) {
            /* two newlines is separator */
            if (strnEQ(ptr, "\r\n\r\n", 4)) {
                break;
            }
            count++; ptr++;
        }
        /* +3: +"\r\n\0" */
        self->header = (char*) safemalloc(sizeof(char) * (count+3));
        self->body = (char*) 
            safemalloc(sizeof(char) * (strlen(self->email->email) - count));
        
        strncpy(self->header, self->email->email, count+2);
        self->header[count+2] = '\0';
        /* +4 to ommit the two newlines ("\r\n\r\n") */
        strcpy(self->body, ptr+4);
    }
}
    
int datify (pTHX_ FILETIME *wintime, int method) {
    dSP;
    time_t time = FileTimeToUnixTime(wintime, NULL);
    struct tm *tstruct;
    (void) POPs; /* removing pending object which is in ST(0) */

    if (method == 0)  /* localtime */
        tstruct = localtime(&time);
    else              /* gmtime */
        tstruct = gmtime(&time);
    
    if (GIMME == G_ARRAY) {
        EXTEND(SP, 9);
        PUSHs(sv_2mortal(newSViv(tstruct->tm_sec)));
        PUSHs(sv_2mortal(newSViv(tstruct->tm_min)));
        PUSHs(sv_2mortal(newSViv(tstruct->tm_hour)));
        PUSHs(sv_2mortal(newSViv(tstruct->tm_mday)));
        PUSHs(sv_2mortal(newSViv(tstruct->tm_mon)));
        PUSHs(sv_2mortal(newSViv(tstruct->tm_year)));
        PUSHs(sv_2mortal(newSViv(tstruct->tm_wday)));
        PUSHs(sv_2mortal(newSViv(tstruct->tm_yday)));
        PUSHs(sv_2mortal(newSViv(tstruct->tm_isdst)));
        PUTBACK;
        return 9;
    } else {
        SV *str = newSVpvf("%s %s %2d %02d:%02d:%02d %d",
                  dayname[tstruct->tm_wday],
                  monname[tstruct->tm_mon],
                  tstruct->tm_mday,
                  tstruct->tm_hour,
                  tstruct->tm_min,
                  tstruct->tm_sec,
                  tstruct->tm_year + 1900);                   
        EXTEND(SP, 1);
        PUSHs(sv_2mortal(str));
        PUTBACK;
        return 1;
    }
}

MODULE = Mail::Transport::Dbx PACKAGE = Mail::Transport::Dbx

INCLUDE: const-xs.inc
PROTOTYPES: DISABLED

DBX *
new (CLASS, dbx)
        char *CLASS;
        SV *dbx;
    PREINIT:
        STRLEN len;
    CODE:
        if (glob_ref(dbx) && !errno)
            RETVAL = dbx_open_stream(sv_to_file(dbx));
        else
            RETVAL = dbx_open(SvPV(dbx, len));

        if (!RETVAL)
            croak("%s", errstr());

    OUTPUT:
        RETVAL

void *
get (self, index)
        DBX *self;
        int index;
    PREINIT:
        void *ret_type;
    CODE:
        ret_type = dbx_get(self, index, 0);
        if (!ret_type)
            XSRETURN_UNDEF;
    OUTPUT:
        RETVAL

int 
error (...)
    CODE:
        RETVAL = dbx_errno;
    OUTPUT:
        RETVAL

char*
errstr (...)
    CODE:
        RETVAL = errstr();
    OUTPUT:
        RETVAL

int
msgcount (self)
        DBX *self;
    CODE:
        RETVAL = self->indexCount;
    OUTPUT:
        RETVAL

void
DESTROY (self)
        DBX *self;
    CODE:
        dbx_close(self);
        

MODULE = Mail::Transport::Dbx PACKAGE = Mail::Transport::Dbx::Email

char *
psubject (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = self->email->psubject;
    OUTPUT:
        RETVAL

char *
subject (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = self->email->subject;
    OUTPUT:
        RETVAL

char *
as_string (self)
        DBX_EMAIL *self;
    CODE:
        if (!(RETVAL = self->email->email)) {
            (void) dbx_get_email_body(self->dbx, self->email);
            if (dbx_errno == DBX_DATA_READ)
                /* see comment in split_mail() */        
                XSRETURN_UNDEF;
            RETVAL = self->email->email;
        }
    OUTPUT:
        RETVAL

char *
header (self)
        DBX_EMAIL *self;
    CODE:
        split_mail(aTHX_ self);
        if (!(RETVAL = self->header))
            XSRETURN_UNDEF;
    OUTPUT:
        RETVAL

char *
body (self)
        DBX_EMAIL *self;
    CODE:
        split_mail(aTHX_ self);
        if (!(RETVAL = self->body))
            XSRETURN_UNDEF;
    OUTPUT:
        RETVAL

char *
msgid (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = self->email->messageid;
    OUTPUT:
        RETVAL

char *
parents_ids (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = self->email->parent_message_ids;
    OUTPUT:
        RETVAL

char *
sender_name (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = self->email->sender_name;
    OUTPUT:
        RETVAL

char *
sender_address (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = self->email->sender_address;
    OUTPUT:
        RETVAL

char *
recip_name (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = self->email->recip_name;
    OUTPUT:
        RETVAL

char *
recip_address (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = self->email->recip_address;
    OUTPUT:
        RETVAL

char *
oe_account_name (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = self->email->oe_account_name;
    OUTPUT:
        RETVAL

char *
oe_account_num (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = self->email->oe_account_num;
    OUTPUT:
        RETVAL

char *
fetched_server (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = self->email->fetched_server;
    OUTPUT:
        RETVAL

void
rcvd_localtime (self)
        DBX_EMAIL *self;
    PPCODE:
        XSRETURN(datify(aTHX_ &(self->email->date), 0));

void
rcvd_gmtime (self)
        DBX_EMAIL *self;
    PPCODE:
        XSRETURN(datify(aTHX_ &(self->email->date), 1));

char *
date_received (self, ...)
        DBX_EMAIL *self;
    PREINIT:
        char *format = "%a %b %e %H:%M:%S %Y";
        STRLEN n_a;
        size_t max_len = 25;
        time_t time;
        struct tm *tstruct;
        char *string;
    CODE:
        if (items > 1)
            format = (char *) SvPV(ST(1), n_a);
        if (items > 2)
            max_len = (int) SvIV(ST(2));   

        time = FileTimeToUnixTime(&(self->email->date), NULL);

        if (items > 3 && SvTRUE(ST(3)))
            tstruct = gmtime(&time);
        else 
            tstruct = localtime(&time);

        string = (char*) safemalloc(sizeof(char) * max_len);
        strftime(string, max_len, format, tstruct);
        RETVAL = string;
    OUTPUT:
        RETVAL

int
is_seen (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = (self->email->flag & DBX_EMAIL_FLAG_ISSEEN) > 0 ? 1 : 0;
    OUTPUT:
        RETVAL

int
is_email (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = 1;
    OUTPUT:
        RETVAL

int
is_folder (self)
        DBX_EMAIL *self;
    CODE:
        RETVAL = 0;
    OUTPUT:
        RETVAL

void
DESTROY (self)
        DBX_EMAIL *self;
    CODE:
        if (self->header)
            safefree(self->header);
        if (self->body)
            safefree(self->body);
        
        dbx_free(self->dbx, self->email);
        safefree(self);
        

MODULE = Mail::Transport::Dbx PACKAGE = Mail::Transport::Dbx::Folder

int
num (self)
        DBX_FOLDER *self;
    CODE:
        RETVAL = self->folder->num;
    OUTPUT:
        RETVAL

int
type (self)
        DBX_FOLDER *self;
    CODE:
        RETVAL = self->folder->type;
    OUTPUT:
        RETVAL

char *
name (self)
        DBX_FOLDER *self;
    CODE:
        RETVAL = self->folder->name;
    OUTPUT:
        RETVAL

char *
file (self)
        DBX_FOLDER *self;
    CODE:
        RETVAL = self->folder->fname;
    OUTPUT:
        RETVAL

int
id (self)
        DBX_FOLDER *self;
    CODE:
        RETVAL = self->folder->id;
    OUTPUT:
        RETVAL

int 
parent_id (self)
        DBX_FOLDER *self;
    CODE:
        RETVAL = self->folder->parentid;
    OUTPUT:
        RETVAL

int
is_email (self)
        DBX_FOLDER *self;
    CODE:
        RETVAL = 0;
    OUTPUT:
        RETVAL

int
is_folder (self)
        DBX_FOLDER *self;
    CODE:
        RETVAL = 1;
    OUTPUT:
        RETVAL
       
DBX *
dbx (self)
        DBX_FOLDER *self;
    PREINIT:
        char *CLASS = "Mail::Transport::Dbx"; /* used in typemap */
    CODE:
        if (!self->folder->fname)
            XSRETURN_UNDEF;
        RETVAL = dbx_open(self->folder->fname);
    OUTPUT:
        RETVAL

void
DESTROY (self)
        DBX_FOLDER *self;
    CODE:
        dbx_free(self->dbx, self->folder);
        safefree(self);
