#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "libdbx/libdbx.h"
#include "libdbx/timeconv.h"

#include "const-c.inc"

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

char * errstr (void) {
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

void split_mail (DBX_EMAIL *self) {
    if (self->header)
        return;
    else {
        char *ptr;
        int count = 0;

        /* email data not yet loaded */
        if (!self->email->email) 
            (void) dbx_get_email_body(self->dbx, self->email);
        
        ptr = self->email->email;
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
            RETVAL = self->email->email;
        }
    OUTPUT:
        RETVAL

char *
header (self)
        DBX_EMAIL *self;
    CODE:
        split_mail(self);
        RETVAL = self->header;
    OUTPUT:
        RETVAL

char *
body (self)
        DBX_EMAIL *self;
    CODE:
        split_mail(self);
        RETVAL = self->body;
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

char *
date_received (self, ...)
        DBX_EMAIL *self;
    PREINIT:
        char *format = "%a %b %e %H:%M:%S %Y";
        STRLEN n_a;
        size_t max_len = 25;
        int method;
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
        free(self);
        

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
        char *CLASS = "Mail::Transport::Dbx";
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
