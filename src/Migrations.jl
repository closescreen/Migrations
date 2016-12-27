"""
julia> # m|> save( filename, force=true)

julia> # m = Migrations.read( filename)

"""
module Migrations

abstract Action

immutable NotImplemented<:Action end



immutable Implemented<:Action
 expr::Expr
 func::Function
 unsafe::Bool
 
 function Implemented(t::AbstractString)
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
    uns = ismatch( r"\bunsafe\b", t)
    new( ex, f, uns)
    
  catch e error("$e\nParsed text:\n$t") end
 end
end



"""
using Migrations

m = Migration()"""
immutable Migration
 check::Action
 migrate::Action
 rollback::Action
 store::Dict{Symbol,Any}
end 

Migration() = Migration( NotImplemented(), NotImplemented(), NotImplemented(), Dict{Symbol,Any}() )


"""
Migrations.Migration() |> check_text(\"""(m)->true\""")
"""
check_text( t::AbstractString) = (m::Migration)->check_text( m, t)



"""
m = Migrations.Migration(); 

check_text( m, \"""(m)->info(\"hello from migration\")\""" )
"""
check_text( m::Migration, t::AbstractString) = Migration( Implemented(t), m.migrate, m.rollback, m.store)



"""
expr::Expr = m|>check_text
"""
check_text( m::Migration) = expr( m.migrate)


#--


"""
Migrations.Migration() |> migrate_text(\"""(m)->info(\"hello from migration\")\""")
"""
migrate_text( t::AbstractString) = (m::Migration)->migrate_text( m, t)



"""
m = Migrations.Migration(); 

migrate_text( m, \"""(m)->info(\"hello from migration\")\""" )
"""
migrate_text( m::Migration, t::AbstractString) = Migration( m.check, Implemented(t), m.rollback, m.store)



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



"""
Migrations.Migration() |> rollback_text(\"""(m)->info(\"hello from rollback\")\""")
"""
rollback_text( t::AbstractString) = (m::Migration)->rollback_text( m, t)



"""
m = Migrations.Migration(); 

rollback_text( m, \"""(m)->info(\"hello from migration\")\""" )
"""
rollback_text( m::Migration, t::AbstractString) = Migration( m.check, m.migrate, Implemented(t), m.store)



"m|>check"
function check( m::Migration) 
 rv = doit( m.check, m)
 isa( rv, Bool) && return rv
 isa( rv, NotImplemented ) && error("Not implemented check() for migration $m")
 error("Bad type $(rv|>typeof) of returned value ($rv). Must be a Bool. check():\n$(m.check.expr)")
end 



"""migrate( m::Migration ) 

migrate( m::Migration, force=true)"""
migrate( m::Migration; force::Bool=false ) =
    if force 
        mg = doit( m.migrate, m)
        Dict( :check=>:skipped, migrate=>mg)
    else
        if ( ch = check( m))::Bool 
            Dict( :check=>ch, :migrate=>:notcalled)
        else
            mg = doit( m.migrate, m)
            Dict( :check=>ch, :migrate=>mg)
        end
    end


"""
m|>migrate

m|>migrate( force=true) # without check()

does migrate if check returns false"""
migrate( ;force::Bool=false) = (m)->migrate( m, force=force)            



"""rollback( m)

rollback( m, force=true) # without check()

does rollback if check() returns true"""
rollback( m::Migration; force::Bool=false) = 
    if force 
        rb = doit( m.rollback, m)
        Dict( :check=>:skipped, :rollback=>rb)
    else        
        if ( ch = check( m))::Bool
            rb = doit( m.rollback, m)
            Dict( :check=>ch, :rollback=>rb)
        else
            Dict( :check=>ch, :rollback=>:notcalled)
        end
    end        


"""m|>rollback

m|>rollback( force=true)
"""
rollback( ;force::Bool=false ) = (m)->rollback( m, force=force)


doit( i::Implemented, args... ) = i.func( args...)
doit( ni::NotImplemented, args... ) = ni


end # module
