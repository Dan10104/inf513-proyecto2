import { useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowRight, MapPin } from 'lucide-react'
import { comercioApi } from '../../api/comercioApi'
import { useCargaApi } from '../../hooks/useCargaApi'
import { useNavegacion } from '../../hooks/useNavegacion'
import { useSesion } from '../../hooks/useSesion'
import { formatearMoneda, nombreRol } from '../../utils/formato'
import { rutaPublica } from '../../utils/rutas'
import Alerta from '../../components/ui/Alerta'
import './InicioPagina.css'

const RESUMEN = { CLIENTE: '/mi-cuenta', PRODUCTOR: '/productor', PERSONAL_FEDER: '/operaciones', ADMINISTRADOR: '/administracion' }

export default function InicioPagina() {
  const { sesion, cargando } = useSesion()
  if (cargando) return <p role="status">Cargando inicio…</p>
  return sesion ? <InicioUsuario sesion={sesion} /> : <InicioVisitante />
}

function InicioUsuario({ sesion }) {
  const { entradas, cargando, error } = useNavegacion()
  const destino = entradas.find((e) => e.ruta === RESUMEN[sesion.rol_activo.codigo])
    ?? entradas.find((e) => e.ruta !== '/')
  return <section className="inicio inicio--cuenta">
    <h1>{nombreRol(sesion.rol_activo.codigo)}</h1>
    {cargando ? <p role="status">Cargando opciones…</p> : error ? <Alerta tipo="error">{error}</Alerta>
      : destino ? <Link className="inicio__accion" to={destino.ruta}>{destino.etiqueta} <ArrowRight size={18} /></Link>
        : <p>Tu contexto actual no tiene otras opciones disponibles.</p>}
  </section>
}

function InicioVisitante() {
  const categorias = useCargaApi(() => comercioApi.filtrosCatalogo(), [])
  const seleccion = useCargaApi(() => comercioApi.catalogo({ q: 'miel' }), [])
  const [fallidas, setFallidas] = useState([])
  const producto = seleccion.datos?.productos?.find((p) => p.imagen_url && !fallidas.includes(p.imagen_url))
  return <div className="inicio">
    <section className={'inicio__portada' + (producto ? ' inicio__portada--foto' : '')}>
      <div className="inicio__texto">
        <h1>Productos de nuestras comunidades</h1>
        <p>Explora los productos de las comunidades afiliadas a FEDER. Consulta su disponibilidad y conoce su origen antes de comprar.</p>
        <Link to="/catalogo" className="inicio__accion">Ver catálogo <ArrowRight size={18} /></Link>
      </div>
      {producto && <Link to={'/catalogo/' + producto.id} className="inicio__producto">
        <span className="inicio__foto"><img src={rutaPublica(producto.imagen_url)} alt="" onError={() => setFallidas((urls) => [...urls, producto.imagen_url])} width="800" height="800" /></span>
        <div className="inicio__ficha">
          <strong>{producto.nombre}</strong><span>{formatearMoneda(producto.precio)}</span>
          {!!producto.comunidades?.length && <small><MapPin size={14} /> {producto.comunidades.join(', ')}</small>}
        </div>
      </Link>}
    </section>
    <section aria-labelledby="categorias-inicio">
      <h2 id="categorias-inicio">Explorar por categoría</h2>
      {categorias.cargando && !categorias.datos && <p role="status">Cargando categorías…</p>}
      {categorias.error && <Alerta tipo="error">{categorias.error} <button onClick={categorias.recargar}>Reintentar</button></Alerta>}
      {categorias.datos && (categorias.datos.categorias?.length ? <ul className="inicio__categorias">
        {categorias.datos.categorias.map((categoria) => <li key={categoria.id}><Link to={'/catalogo?categoria=' + categoria.id}>
          {categoria.nombre}<ArrowRight size={16} aria-hidden="true" />
        </Link></li>)}</ul> : <p>Aún no hay categorías publicadas.</p>)}
    </section>
  </div>
}
