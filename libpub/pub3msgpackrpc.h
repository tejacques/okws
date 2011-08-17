// -*-c++-*-

#pragma once

#include "async.h"
#include "pub3.h"
#include "tame_rendezvous.h"

namespace pub3 {

  namespace msgpack {

    enum {
      REQUEST  = 0, //  [0, msgid, method, param]
      RESPONSE = 1, //  [1, msgid, error, result]
      NOTIFY = 2   //  [2, method, param]
    };

    //========================================

    typedef int64_t seqid_t;

    //========================================

    struct callres_t {
      callres_t () : err_code (RPC_SUCCESS) {}
      callres_t (clnt_stat s, str m);
      void set_err_code (clnt_stat e) { err_code = e; }
      clnt_stat err_code;
      ptr<expr_t> res;
      ptr<expr_t> err_msg;
    };

    //========================================

    typedef event<int, ptr<expr_t> >::ref ev_t;
    typedef event<callres_t>::ref callev_t;

    //========================================

    class dependent_t {
    public:
      virtual void eof_hook (int rc) = 0;
      list_entry<dependent_t> _lnk;
    };

    //========================================

    class asrv;

    class axprt_inner : public virtual refcount {
    private:
      int _errno;
      int _fd;
      strbuf _inbuf;
      u_int32_t _seqid;
      str _remote;
      tame::lock_t _read_lock, _write_lock;
      evv_t::ptr _read_stop, _write_stop;
      rendezvous_t<> _read_rv, _write_rv;

      qhash<u_int32_t, callev_t::ptr> _calls;
      qhash<str, ptr<asrv> > _dispatch;
      ptr<asrv> _dispatch_def;

      axprt_inner (int fd);
      void close (int en);
      void recv_json (size_t lim, size_t ps, ev_t ev, CLOSURE);
      bool is_open () const { return _fd >= 0; }
      str get_str (size_t bytes) const;
      friend class refcounted<axprt_inner>;

      u_int32_t seqid () ;
      void error (str msg);
      str get_remote ();
      void waitread (evv_t ev, CLOSURE);
      void waitwrite (evv_t ev, CLOSURE);
      void kill_clients ();
      void kill_servers ();
      void dispatch_reply (ptr<expr_list_t> l, int64_t seqid);
      void dispatch_call (ptr<expr_list_t> l, int64_t typ, int64_t seqid);

    public:
      void stop ();
      static ptr<axprt_inner> alloc (int fd);
      void send (ptr<const expr_t> x, evb_t::ptr ev = NULL, CLOSURE);
      void recv (ev_t ev, CLOSURE);
      void dispatch (CLOSURE);
      void call (str mthd, ptr<const expr_t> arg, callev_t::ptr ev, CLOSURE);
      void register_asrv (str prot, ptr<asrv> v);
      
      ~axprt_inner ();
    };
    
    //========================================

    class axprt : public virtual refcount {
      ptr<axprt_inner> _xi;
      axprt (int fd);
      friend class refcounted<axprt>;
      void run ();
      
    public:
      void call (str mthd, ptr<const expr_t> arg, callev_t::ptr ev);
      void send (ptr<const expr_t> x, evb_t::ptr ev = NULL);
      void register_asrv (str prot, ptr<asrv> v);
      static ptr<axprt> alloc (int fd);
      ~axprt ();
    };

    //========================================

    class aclnt : public virtual refcount {
    private:
      ptr<axprt> _x;
      str _prog;
      aclnt (ptr<axprt> x, str prog);
      ~aclnt ();
      friend class refcounted<aclnt>;
      str mkmthd (str s) const;

    public:
      void call (str method, ptr<const expr_t> arg,
		 callev_t::ptr ev, CLOSURE);

      static ptr<aclnt> alloc (ptr<axprt> x, str prog);
    };

    //========================================

    class svccb {
      seqid_t _sid;
      str _mthd;
      ptr<expr_t> _arg;
      ptr<asrv> _asrv;
      ptr<expr_t> _err, _res;
      bool _eof;
      void send ();
    public:
      svccb (seqid_t sid, str m, ptr<expr_t> arg, ptr<asrv> v);
      svccb ();
      str method () const { return _mthd; }
      ptr<expr_t> arg () { return _arg; }
      void reply (ptr<expr_t> x = NULL);
      void reject (accept_stat stat);
      ptr<expr_t> to_json () const;
      pub3::obj_dict_t rpc_err_obj ();
    };

    typedef callback<void, svccb >::ref asrvcb_t ;

    //========================================

    class asrv : public virtual refcount {
      ptr<axprt> _x;
      str _prog;
      asrvcb_t _cb;
      asrv (ptr<axprt> x, str prog, asrvcb_t cb);
      friend class refcounted<asrv>;
    public:
      void error (str s);
      void eof ();
      void reply (const svccb &b);
      static ptr<asrv> alloc (ptr<axprt> x, str prog, asrvcb_t cb);
      void dispatch (seqid_t sid, str mthd, ptr<expr_t> arg);
      ptr<axprt> getx () { return _x; }
    };

    //========================================
    
  }

};
