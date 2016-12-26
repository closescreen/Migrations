"""
julia> # m|> save( filename, force=true)

julia> # m = Migrations.read( filename)

julia> # m|>migrate

julia> # m|>rollback

"""
module Migrations

abstract Action

immutable NotImplemented<:Action end



immutable Implemented<:Action
 expr::Expr
 func::Function
 unsafe::Bool
 
 function Implemented(t::AbstractString)
    ex = parse(t)
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
 end
end



"""
using Migrations

m = Migration()"""
type Migration
 migrate::Action
 rollback::Action
end 

Migration() = Migration( NotImplemented(), NotImplemented() )


"""
Migrations.Migration() |> migrate_text(\"""()->info(\"hello from migration\")\""")
"""
migrate_text( t::AbstractString) = (m::Migration)->migrate_text( m, t)



"""
m = Migrations.Migration(); 

migrate_text( m, \"""()->info(\"hello from migration\")\""" )
"""
migrate_text( m::Migration, t::AbstractString) = Migration( Implemented(t), m.rollback)



"""
expr::Expr = m|>migrate_text
"""
migrate_text( m::Migration) = expr( m.migrate)



"""
expr::Expr = m|>rollback_text
"""
rollback_text( m::Migration) = expr( m.rollback)


expr( ni::NotImplemented) = ni
expr( imp::Implemented) = imp.expr



"""
Migrations.Migration() |> rollback_text(\"""()->info(\"hello from rollback\")\""")
"""
rollback_text( t::AbstractString) = (m::Migration)->rollback_text( m, t)



"""
m = Migrations.Migration(); 

rollback_text( m, \"""()->info(\"hello from migration\")\""" )
"""
rollback_text( m::Migration, t::AbstractString) = Migration( m.migrate, Implemented(t))

"m|>migrate"
migrate( m::Migration) = doit( m.migrate)

"m|>rollback"
rollback( m::Migration) = doit( m.rollback)

doit( i::Implemented) = i.func()
doit( ni::NotImplemented) = ni








end # module
