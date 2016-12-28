"""
julia> Migration() |>

        cache_text( s\"""(m)-> (KH, server) = \"chouse_conf.jl\"|>include \""" )|>
          
        check_text( s\""" function (m)
         (KH, server) = cached(m)
         dbexists = any( _->ismatch( r\"RND600\", _), KH.READONLY( server, \"SHOW DATABASES\")|>readlines )
        end \""") |>

        migrate_text( s\""" function(m)
         (KH, server) = cached(m)
         KH.MODIFY( server, \"CREATE DATABASE RND600\")
        end \""", danger=false) |>

        rollback_text( s\""" function(m)
         (KH, server) = cached(m)
         KH.MODIFY( server, \"DROP DATABASE RND600\" )
        end \""") |> migrate 
        
        # or ... |> rollback( DANGER=true)
        
        # or ... |> check
"""
module Migrations


abstract Action

immutable NotImplemented<:Action end


immutable Implemented<:Action
 expr::Expr
 func::Function
 danger::Bool
 
 function Implemented( t::AbstractString; danger=false)
  try ex = parse(t)
    
    if isa( ex, Expr)
        ex.head == :incomplete && error("Incomplete expression:\n$t")
    else
        error("Bad type: $(ex|>typeof). Must be Expr. \nText: $t")
    end 
    f = eval(ex)
    
    if !isa( f, Function)
        error("Bad type: $(f|>typeof). Must be a Function. \nExpr: $ex")
    end
    
    !danger && ismatch( r"\bDROP\b", t) &&
        "Found smth dangerous in text:\n$t\nYou must mark action as danger=true"|>error
        
    new( ex, f, danger)
    
  catch e error("$e\nParsed text:\n$t") end
 end
end


abstract Cache

immutable EmptyCache<:Cache end

immutable FullCache{T}<:Cache
 value::T
end 


"""
using Migrations

m = Migration()"""
immutable Migration
 cache::Action
 cached::Cache
 check::Action
 migrate::Action
 rollback::Action
end 
export Migration


Migration(; cache::Action=NotImplemented(),
            cached::Cache=EmptyCache(),
            check::Action=NotImplemented(),
            migrate::Action=NotImplemented(),
            rollback::Action=NotImplemented() ) = Migration( cache, cached, check, migrate, rollback )


"""
Migrations.Migration() |> cache_text(\"""(m)->true\""")
"""
cache_text( t::AbstractString) = (m::Migration)->cache_text( m, t)
export cache_text


"""
m = Migrations.Migration(); 

cache_text( m, \"""(m)->info(\"hello from migration\")\""" )
"""
cache_text( m::Migration, t::AbstractString) = 
    Migration( cache=Implemented(t), cached=m.cached, check=m.check, migrate=m.migrate, rollback=m.rollback)



"""
expr::Expr = m|>cache_text # return 'cache' action from migration
"""
cache_text( m::Migration) = expr( m.cache)




"""
Migrations.Migration() |> check_text(\"""(m)->true\""")
"""
check_text( t::AbstractString) = (m::Migration)->check_text( m, t)
export check_text


"""
m = Migrations.Migration(); 

check_text( m, \"""(m)->info(\"hello from migration\")\""" )
"""
check_text( m::Migration, t::AbstractString) = 
    Migration( cache=m.cache, cached=m.cached, check=Implemented(t), migrate=m.migrate, rollback=m.rollback)



"""
expr::Expr = m|>check_text
"""
check_text( m::Migration) = expr( m.check)



"""
Migrations.Migration() |> migrate_text(\"""(m)->info(\"hello from migration\")\""")
"""
migrate_text( t::AbstractString; danger::Bool=true ) = 
    (m::Migration)->migrate_text( m, t, danger=danger)
export migrate_text


"""
m = Migrations.Migration(); 

migrate_text( m, \"""(m)->info(\"hello from migration\")\""" )
"""
migrate_text( m::Migration, t::AbstractString; danger::Bool=true) = 
    Migration( cache=m.cache, cached=m.cached, check=m.check, migrate=Implemented(t,danger=danger), rollback=m.rollback)



"""
expr::Expr = m|>migrate_text
"""
migrate_text( m::Migration) = expr( m.migrate)



expr( ni::NotImplemented) = ni
expr( imp::Implemented) = imp.expr



"""
expr::Expr = m|>rollback_text
"""
rollback_text( m::Migration) = expr( m.rollback)
export rollback_text


"""
Migrations.Migration() |> rollback_text(\"""(m)->info(\"hello from rollback\")\""")
"""
rollback_text( t::AbstractString; danger::Bool=true) = (m::Migration)->rollback_text( m, t, danger=danger)



"""
m = Migrations.Migration(); 

rollback_text( m, \"""(m)->info(\"hello from migration\")\""" )
"""
rollback_text( m::Migration, t::AbstractString; danger::Bool=true) = 
    Migration( cache=m.cache, cached=m.cached, check=m.check, migrate=m.migrate, rollback=Implemented( t, danger=danger))



"""
Returns old m::Migration if cache() not implemented, and return new with cached value otherwise

m|>cache
"""
function cache( m::Migration; debug::Bool=false)::Migration
 if isa( m.cached, EmptyCache )
    rv = doit( m.cache, m, debug=debug, prefix="Run cache()")
    isa( rv, NotImplemented ) && return m
    isa( rv, Void ) && error("cache() not return any value! Must return something.\n$(m.cache.expr)")
    Migration( cache=m.cache, cached=FullCache(rv), check=m.check, migrate=m.migrate, rollback=m.rollback )
 else
    m
 end
end
export cache


"Returns migrations cached value (returned from cache())"
cached(m::Migration) = isa( m.cached, FullCache) ?
    m.cached.value :
        isa( m.cache, NotImplemented ) ?
            error("Migration has not cached value, because cache() not implemented.") : 
            error("Migration has not cached value. Forgot to call cache()? cache expression:\n $(m.cache.expr)")
export cached



"""
Checks is migration successed.

m|>check"""
function check( m::Migration; debug::Bool=false, prefix::AbstractString="Run check()")
 isa( m.cached, EmptyCache) && ( m = cache( m, debug=debug))
 rv = doit( m.check, m, debug=debug, prefix=prefix)
 if isa( rv, Bool) 
    debug && info("Return: $rv")
    return rv
 end
 isa( rv, NotImplemented ) && error("Not implemented check() for migration $m")
 error("Bad type $(rv|>typeof) of returned value ($rv). Must be a Bool. check():\n$(m.check.expr)")
end 
export check


function migrate( m::Migration; checking::Bool=true, DANGER::Bool=false, debug::Bool=true )
    isa( m.cached, EmptyCache) && (m = cache( m, debug=debug))
    if checking
        chk1 = check( m, debug=true, prefix="Check before migrate()")::Bool
        chk1 && return Dict(:check_before=>chk1, :migrate=>:not_called, :resume=>:not_need)
        mgr = doit( m.migrate, m, DANGER=DANGER, debug=debug, prefix="migrate()")
        chk2 = check( m, debug=true, prefix="Check after migrate()")::Bool
        !chk2 && warn( "Check return $chk2 after migration!")
        Dict( :check_before=>chk1, :migrate=>mgr, :check_after=>chk2, :resume=>(chk2? :success : :fail) )
    else
        mgr = doit( m.migrate, m, DANGER=DANGER, debug=debug, prefix="migrate() without checking" )
        Dict( :check_before=>:not_called, :migrate=>mgr, :check_after=>:not_called, :resume=>:not_checked_success)
    end
end
export migrate


"""
m|>migrate

m|>migrate( check=false) # without check()

does migrate if check returns false"""
migrate( ;checking::Bool=true, DANGER::Bool=false, debug::Bool=true) = (m)->migrate( m, checking=checking, DANGER=DANGER, debug=debug)            



"""rollback( m)

rollback( m, check=false) # without check()

does rollback if check() returns true"""
function rollback( m::Migration; checking::Bool=true, DANGER::Bool=false, debug::Bool=true)
    isa( m.cached, EmptyCache) && ( m = cache( m, debug=debug))
    if checking 
        ch1 = check( m, debug=true, debug=debug, prefix="Checking before rollback")::Bool
        !ch1 && return Dict( :check_before=>ch1, :rollback=>:not_called, :resume=>:not_need)
        rbk = doit( m.rollback, m, DANGER=DANGER, debug=debug, prefix="rollback()")
        ch2 = check( m, debug=true, prefix="Checking after rollback")::Bool
        ch2 && warn("Check after rollback return $ch2!")
        Dict( :check_before=>ch1, :rollback=>rbk, :check_after=>ch2, :resume=>(ch2? :fail : :success))
    else        
        rbk = doit( m.rollback, m, DANGER=DANGER, debug=debug, prefix="rollback()")
        Dict( :check_before=>:skipped, :rollback=>rbk, :check_after=>:skipped, :resume=>:not_checked_success)
    end        
end
export rollback

"""m|>rollback

m|>rollback( check=false)
"""
rollback( ;checking::Bool=true, DANGER::Bool=false, debug::Bool=true ) = (m)->rollback( m, checking=checking, DANGER=DANGER, debug=debug)

 
function doit( i::Implemented, args... ; DANGER=false, debug::Bool=false, prefix::AbstractString="" )
    !DANGER && i.danger && error("Canceled dangerous action. Must be called with DANGER=true.\n$(i.expr)")
    debug && info("$prefix call:\n$(i.expr)")
    try rv = i.func( args...)
        debug && info("$prefix return: $rv")
        rv
    catch e 
        error("$prefix: $e\n$(i.expr)\nArguments:\n$(args...)") 
    end
end        
        
doit( ni::NotImplemented, args...; DANGER=false, debug::Bool=false, prefix::AbstractString="" )::NotImplemented = ni



end # module
