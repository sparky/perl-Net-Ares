/* vim: ts=4:sw=4:fdm=marker: */

/*
 * Perl interface for libares. Check out the file README for more info.
 */

/*
 * Copyright (C) 2000, 2001, 2002, 2005, 2008 Daniel Stenberg, Cris Bailiff, et al.
 * Copyright (C) 2011 Przemyslaw Iskra.
 * You may opt to use, copy, modify, merge, publish, distribute and/or
 * sell copies of the Software, and permit persons to whom the
 * Software is furnished to do so, under the terms of the MPL or
 * the MIT/X-derivate licenses. You may pick one of these licenses.
 */
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <ares.h>

#ifndef Newx
# define Newx(v,n,t)	New(0,v,n,t)
# define Newxc(v,n,t,c)	Newc(0,v,n,t,c)
# define Newxz(v,n,t)	Newz(0,v,n,t)
#endif

#ifndef hv_stores
# define hv_stores(hv,key,val) hv_store( hv, key, sizeof( key ) - 1, val, 0 )
#endif
#ifndef hv_fetchs
# define hv_fetchs(hv,key,store) hv_fetch( hv, key, sizeof( key ) - 1, store );
#endif

#ifndef CLEAR_ERRSV
# define CLEAR_ERRSV()					\
	STMT_START {						\
		sv_setpvn( ERRSV, "", 0 );		\
		if ( SvMAGICAL( ERRSV ) )		\
			mg_free( ERRSV );			\
		SvPOK_only( ERRSV );			\
	} STMT_END
#endif

#ifndef croak_sv
# define croak_sv( arg )		\
	STMT_START {				\
		SvSetSV( ERRSV, arg );	\
		croak( NULL );			\
	} STMT_END
#endif

#define die_code( pkg, num )			\
	STMT_START {						\
		SV *errsv = sv_newmortal();		\
		sv_setref_iv( errsv, "Net::Ares::" pkg "::Code", num ); \
		croak_sv( errsv );				\
	} STMT_END


#ifndef mPUSHs
# define mPUSHs( sv ) PUSHs( sv_2mortal( sv ) )
#endif
#ifndef mXPUSHs
# define mXPUSHs( sv ) XPUSHs( sv_2mortal( sv ) )
#endif
#ifndef PTR2nat
# define PTR2nat(p)	(PTRV)(p)
#endif


#define ARES_DIE( ret )			\
	STMT_START {				\
		int code = (ret);		\
		if ( code != ARES_SUCCESS ) {	\
			SV *errsv = sv_newmortal();	\
			sv_setref_iv( errsv, "Net::Ares::Code", code );	\
			croak_sv( errsv );	\
		}						\
	} STMT_END


#if 0

/*
 * Convenient way to copy SVs
 */
#define SvREPLACE( dst, src ) \
	STMT_START {						\
		SV *src_ = (src);				\
		if ( dst )						\
			sv_2mortal( dst );			\
		if ( (src_) && SvOK( src_ ) )	\
			dst = newSVsv( src_ );		\
		else							\
			dst = NULL;					\
	} STMT_END

/*
 * create a reference for perl callbacks
 */
#define SELF2PERL( obj ) \
	sv_bless( newRV_inc( (obj)->perl_self ), SvSTASH( (obj)->perl_self ) )

typedef struct {
	/* function that will be called */
	SV *func;

	/* user data */
	SV *data;
} callback_t;

typedef struct pares_easy_s pares_easy_t;
typedef struct pares_form_s pares_form_t;
typedef struct pares_share_s pares_share_t;
typedef struct pares_multi_s pares_multi_t;

static struct ares_slist *
pares_array2slist( pTHX_ struct ares_slist *slist, SV *arrayref )
{
	AV *array;
	int array_len, i;

	if ( !SvOK( arrayref ) || !SvROK( arrayref ) )
		croak( "not an array" );

	array = (AV *) SvRV( arrayref );
	array_len = av_len( array );

	for ( i = 0; i <= array_len; i++ ) {
		SV **sv;
		char *string;

		sv = av_fetch( array, i, 0 );
		if ( !SvOK( *sv ) )
			continue;
		string = SvPV_nolen( *sv );
		slist = ares_slist_append( slist, string );
	}

	return slist;
}

typedef struct simplell_s simplell_t;
struct simplell_s {
	/* next in the linked list */
	simplell_t *next;

	/* ares option it belongs to */
	PTRV key;

	/* the actual data */
	void *value;
};

#if 0
static void *
pares_simplell_get( pTHX_ simplell_t *start, PTRV key )
{
	simplell_t *now = start;

	if ( now == NULL )
		return NULL;

	while ( now ) {
		if ( now->key == key )
			return &(now->value);
		if ( now->key > key )
			return NULL;
		now = now->next;
	}

	return NULL;
}
#endif


static void *
pares_simplell_add( pTHX_ simplell_t **start, PTRV key )
{
	simplell_t **now = start;
	simplell_t *tmp = NULL;

	while ( *now ) {
		if ( (*now)->key == key )
			return &( (*now)->value );
		if ( (*now)->key > key )
			break;
		now = &( (*now)->next );
	}

	tmp = *now;
	Newx( *now, 1, simplell_t );
	(*now)->next = tmp;
	(*now)->key = key;
	(*now)->value = NULL;

	return &( (*now)->value );
}

static void *
pares_simplell_del( pTHX_ simplell_t **start, PTRV key )
{
	simplell_t **now = start;

	while ( *now ) {
		if ( (*now)->key == key ) {
			void *ret = (*now)->value;
			simplell_t *tmp = *now;
			*now = (*now)->next;
			Safefree( tmp );
			return ret;
		}
		if ( (*now)->key > key )
			return NULL;
		now = &( (*now)->next );
	}
	return NULL;
}

#define SIMPLELL_FREE( list, freefunc )			\
	STMT_START {								\
		if ( list ) {							\
			simplell_t *next, *now = list;		\
			do {								\
				next = now->next;				\
				freefunc( now->value );			\
				Safefree( now );				\
			} while ( ( now = next ) != NULL );	\
		}										\
	} STMT_END


/* generic function for our callback calling needs */
static IV
pares_call( pTHX_ callback_t *cb, int argnum, SV **args )
{
	dSP;
	int i;
	IV status;
	SV *olderrsv = NULL;
	int method_call = 0;

	if ( ! cb->func || ! SvOK( cb->func ) ) {
		warn( "callback function is not set\n" );
		return -1;
	} else if ( SvROK( cb->func ) )
		method_call = 0;
	else if ( SvPOK( cb->func ) )
		method_call = 1;
	else {
		warn( "Don't know how to call the callback\n" );
		return -1;
	}

	ENTER;
	SAVETMPS;

	PUSHMARK( SP );

	EXTEND( SP, argnum );
	for ( i = 0; i < argnum; i++ )
		mPUSHs( args[ i ] );

	if ( cb->data )
		mXPUSHs( newSVsv( cb->data ) );

	PUTBACK;

	if ( SvTRUE( ERRSV ) )
		olderrsv = sv_2mortal( newSVsv( ERRSV ) );

	if ( method_call )
		call_method( SvPV_nolen( cb->func ), G_SCALAR | G_EVAL );
	else
		call_sv( cb->func, G_SCALAR | G_EVAL );

	SPAGAIN;

	if ( SvTRUE( ERRSV ) ) {
		/* cleanup after the error */
		(void) POPs;
		status = -1;
	} else {
		status = POPi;
	}

	if ( olderrsv )
		sv_setsv( ERRSV, olderrsv );

	PUTBACK;
	FREETMPS;
	LEAVE;

	return status;
}

#define PERL_ARES_CALL( cb, arg ) \
	pares_call( aTHX_ (cb), sizeof( arg ) / sizeof( (arg)[0] ), (arg) )

#endif

static int
pares_nodup( pTHX_ MAGIC *mg, CLONE_PARAMS *param )
{
	warn( "Net::Ares does not support cloning\n" );
	mg->mg_ptr = NULL;
	return 1;
}

static void *
pares_getptr( pTHX_ SV *self, MGVTBL *vtbl )
{
	MAGIC *mg;

	if ( !self )
		return NULL;

	if ( !SvOK( self ) )
		return NULL;

	if ( !SvROK( self ) )
		return NULL;

	if ( !sv_isobject( self ) )
		return NULL;

	for ( mg = SvMAGIC( SvRV( self ) ); mg != NULL; mg = mg->mg_moremagic ) {
		if ( mg->mg_type == PERL_MAGIC_ext && mg->mg_virtual == vtbl )
			return mg->mg_ptr;
	}

	return NULL;
}


static void *
pares_getptr_fatal( pTHX_ SV *self, MGVTBL *vtbl, const char *name,
		const char *type )
{
	void *ret;
	SV **perl_self;

	if ( ! sv_derived_from( self, type ) )
		croak( "'%s' is not a %s object", name, type );

	ret = pares_getptr( aTHX_ self, vtbl );

	if ( ret == NULL )
		croak( "'%s' is an invalid %s object", name, type );

	/*
	 * keep alive: this trick makes sure user will not destroy last
	 * existing reference from inside of a callback.
	 */
	perl_self = ret;
	if ( perl_self && *perl_self )
		sv_2mortal( newRV_inc( *perl_self ) );

	return ret;
}


static void
pares_setptr( pTHX_ SV *self, MGVTBL *vtbl, void *ptr )
{
	MAGIC *mg;

	if ( pares_getptr( aTHX_ self, vtbl ) )
		croak( "object already has our pointer" );

	mg = sv_magicext( SvRV( self ), 0, PERL_MAGIC_ext,
		vtbl, (const char *) ptr, 0 );
	mg->mg_flags |= MGf_DUP;
}

/* code shamelessly stolen from ExtUtils::Constant */
static void
pares_constant_add( pTHX_ HV *hash, const char *name, I32 namelen,
		SV *value )
{
#if PERL_REVISION == 5 && PERL_VERSION >= 9
	SV **sv = hv_fetch( hash, name, namelen, TRUE );
	if ( !sv )
		croak( "Could not add key '%s' to %%Net::Ares::", name );

	if ( SvOK( *sv ) || SvTYPE( *sv ) == SVt_PVGV ) {
		newCONSTSUB( hash, name, value );
	} else {
		SvUPGRADE( *sv, SVt_RV );
		SvRV_set( *sv, value );
		SvROK_on( *sv );
		SvREADONLY_on( value );
	}
#else
	newCONSTSUB( hash, (char *)name, value );
#endif
}

struct iv_s {
	const char *name;
	I32 namelen;
	IV value;
};
#define IV_CONST( c ) \
	{ #c, sizeof( #c ) - 1, c }
struct pv_s {
	const char *name;
	I32 namelen;
	const char *value;
	I32 valuelen;
};
#define PV_CONST( c ) \
	{ #c, sizeof( #c ) - 1, c, sizeof( c ) - 1 }

struct pares_object_s {
	/* this perl object */
	SV *perl_self;

	/* ares channel */
	ares_channel channel;
};

typedef struct pares_object_s pares_object_t;
typedef pares_object_t *Net__Ares;


static pares_object_t *
pares_new( pTHX_ SV *options )
{
	pares_object_t *ares;
	ares_channel channel;
	int code;

	code = ares_init( &channel );
	ARES_DIE( code );

	Newxz( ares, 1, pares_object_t );
	ares->channel = channel;

	return ares;
}

static pares_object_t *
pares_dup( pTHX_ pares_object_t *source )
{
	pares_object_t *ares;
	ares_channel channel;
	int code;

	code = ares_dup( &channel, source->channel );
	ARES_DIE( code );

	Newxz( ares, 1, pares_object_t );
	ares->channel = channel;

	return ares;
}

static int
pares_free( pTHX_ SV *sv, MAGIC *mg )
{
	if ( mg->mg_ptr ) {
		pares_object_t *ares = (void *)mg->mg_ptr;

		/* prevent recursive destruction */
		SvREFCNT( sv ) = 1 << 30;

		/* WARNING: this will call callbacks */
		ares_destroy( ares->channel );

		Safefree( ares );

		SvREFCNT( sv ) = 0;
	}
	return 0;
}

static MGVTBL pares_vtbl = {
	NULL, NULL, NULL, NULL
	,pares_free
	,NULL
	,pares_nodup
#ifdef MGf_LOCAL
	,NULL
#endif
};



/* default base object */
#define HASHREF_BY_DEFAULT		newRV_noinc( sv_2mortal( (SV *) newHV() ) )

MODULE = Net::Ares	PACKAGE = Net::Ares

BOOT:
	{
		/* XXX 1: this is _not_ thread safe */
		static int run_once = 0;
		if ( !run_once++ ) {
			int code;
			code = ares_library_init( ARES_LIB_INIT_ALL );
			ARES_DIE( code );
			atexit( ares_library_cleanup );
		}
	}
	{
		dTHX;
		HV *symbol_table = get_hv( "Net::Ares::", GV_ADD );
		static const struct iv_s values_for_iv[] = {
#include "ares-constants.h.inc"
			IV_CONST( ARES_VERSION_MAJOR ),
			IV_CONST( ARES_VERSION_MINOR ),
			IV_CONST( ARES_VERSION_PATCH ),
			IV_CONST( ARES_VERSION ),
			{ NULL, 0, 0 }
		};
		static const struct pv_s values_for_pv[] = {
			PV_CONST( ARES_COPYRIGHT ),
			PV_CONST( ARES_VERSION_STR ),
			{ NULL, 0, NULL, 0 }
		};
		const struct iv_s *value_for_iv = values_for_iv;
		const struct pv_s *value_for_pv = values_for_pv;
		while ( value_for_iv->name ) {
			pares_constant_add( aTHX_ symbol_table,
				value_for_iv->name, value_for_iv->namelen,
				newSViv( value_for_iv->value ) );
			++value_for_iv;
		}
		while ( value_for_pv->name ) {
			pares_constant_add( aTHX_ symbol_table,
				value_for_pv->name, value_for_pv->namelen,
				newSVpvn( value_for_pv->value, value_for_pv->valuelen ) );
			++value_for_pv;
		}


		++PL_sub_generation;
	}

PROTOTYPES: ENABLE

SV *
version()
	PROTOTYPE: ;$
	INIT:
		int ver_num;
		const char *ver_str;
	CODE:
		ver_str = ares_version( &ver_num );

		RETVAL = newSVpv( ver_str, 0 );
		SvUV_set( RETVAL, ver_num );
		SvIOK_on( RETVAL );
	OUTPUT:
		RETVAL


int
CLONE_SKIP( pkg )
	SV *pkg
	CODE:
		(void) pkg;
		RETVAL = 1;
	OUTPUT:
		RETVAL


void
new( sclass="Net::Ares", base=HASHREF_BY_DEFAULT, options=NULL )
	const char *sclass
	SV *base
	SV *options
	PREINIT:
		pares_object_t *ares;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		ares = pares_new( aTHX_ options );

		pares_setptr( aTHX_ base, &pares_vtbl, ares );
		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		ares->perl_self = SvRV( ST(0) );
		XSRETURN(1);


void
dup( ares, base=HASHREF_BY_DEFAULT )
	Net::Ares ares
	SV *base
	PREINIT:
		pares_object_t *clone;
		const char *sclass;
		HV *stash;
	PPCODE:
		if ( ! SvOK( base ) || ! SvROK( base ) )
			croak( "object base must be a valid reference\n" );

		sclass = sv_reftype( SvRV( ST(0) ), TRUE );
		clone = pares_dup( aTHX_ ares );

		pares_setptr( aTHX_ base, &pares_vtbl, clone );
		stash = gv_stashpv( sclass, 0 );
		ST(0) = sv_bless( base, stash );

		ares->perl_self = SvRV( ST(0) );
		XSRETURN(1);


void
cancel( ares )
	Net::Ares ares
	CODE:
		ares_cancel( ares->channel );


void
set_local_ip4( ares, local_ip )
	Net::Ares ares
	SV *local_ip
	PREINIT:
		unsigned int ip;
		const unsigned char *src;
		STRLEN len;
	CODE:
		if ( SvOK( local_ip ) )
			croak( "Invalid local_ip." );

		src = (const unsigned char *) SvPV( local_ip, len );
		if ( len != sizeof( unsigned int ) )
			croak( "Invalid local_ip size." );

		ip = src[0] << 24 | src[1] << 16 | src[2] << 8 | src[3];

		ares_set_local_ip4( ares->channel, ip );


void
set_local_ip6( ares, local_ip6 )
	Net::Ares ares
	SV *local_ip6
	PREINIT:
		const unsigned char *src;
		STRLEN len;
	CODE:
		if ( SvOK( local_ip6 ) )
			croak( "Invalid local_ip6." );

		src = (const unsigned char *) SvPV( local_ip6, len );
		if ( len != 16 )
			croak( "Invalid local_ip6 size." );

		ares_set_local_ip6( ares->channel, src );


void
set_local_dev( ares, local_dev_name )
	Net::Ares ares
	SV *local_dev_name
	CODE:
		if ( SvOK( local_dev_name ) )
			croak( "Invalid local_dev_name." );

		ares_set_local_dev( ares->channel, SvPV_nolen( local_dev_name ) );

=for later

void
set_socket_callback( ares, callback, userdata=NULL )
	Net::Ares ares
	SV *local_dev_name
	SV *userdata
	CODE:
		/* TODO */

void
send( ares, query, callback, userdata=NULL )
	CODE:
		/* */

void
query( ares, name, dnsclass, type, callback, userdata=NULL )
	CODE:
		/* */

void
search( ares, name, dnsclass, type, callback, userdata=NULL )
	CODE:
		/* */

void
gethostbyname( ares, name, family, callback, userdata=NULL )
	CODE:
		/* XXX */

void
gethostbyname_file( ares, name, family, host )
	CODE:
		/* */

void
gethostbyaddr( ares, addr, family, callback, userdata=NULL )
	CODE:
		/* */

void
getnameinfo( ares, sa, flags, callback, userdata=NULL )
	CODE:
		/* */

void
fds( ares )
	Net::Ares ares
	PPCODE:
		/* XXX: return ( $rfds, $wfds ) */

void
getsock( ares )
	Net::Ares ares
	PPCODE:
		/* ??? */

SV *
timeout( ares, max=NULL )
	Net::Ares ares
	SV *max;
	CODE:
		/* XXX */
	OUTPUT:
		RETVAL

void
process( ares, read_fds, write_fds )
	CODE:
		/* XXX */

void
process_fd( ares, read_fd, write_fd )
	CODE:
		/* ??? */

void
mkquery( name, dnsclass, type, id, rd, buf )
	CODE:
		/* */

void
set_servers( ares, servers )
	Net::Ares ares
	SV *servers
	CODE:
		/* ??? */

void
set_servers_csv( ares, servers )
	Net::Ares ares
	SV *servers
	CODE:
		/* ??? */

void
get_servers( ares )
	Net::Ares ares
	CODE:
		/* ??? */


=cut

SV *
strerror( ... )
	PROTOTYPE: $;$
	PREINIT:
		const char *errstr;
	CODE:
		if ( items < 1 || items > 2 )
			croak( "Usage: Net::Ares::strerror( [ares], errnum )" );
		errstr = ares_strerror( SvIV( ST( items - 1 ) ) );
		RETVAL = newSVpv( errstr, 0 );
	OUTPUT:
		RETVAL
