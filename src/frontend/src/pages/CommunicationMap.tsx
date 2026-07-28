import { useCallback, useEffect, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import ReactFlow, {
  addEdge, Background, Controls, MiniMap,
  useEdgesState, useNodesState, type Connection,
  type Edge, type Node, MarkerType,
} from 'reactflow';
import 'reactflow/dist/style.css';
import { deleteGraphEdge, getDatabases, getGraphEdges, getProjects, saveGraphEdges } from '../lib/api';
import type { GraphEdgeDto } from '../lib/api';

const ENGINE_COLOR: Record<string, string> = {
  Oracle: '#ef4444', PostgreSQL: '#3b82f6', SqlServer: '#8b5cf6',
  MySQL: '#22c55e', MongoDB: '#f59e0b', Unknown: '#94a3b8',
};

const CONFIDENCE_LABEL: Record<string, string> = {
  High: '✅', Medium: '⚠️', Low: '❓', Unverified: '🔵',
};

const EDGE_STYLE: Record<string, React.CSSProperties> = {
  High:       { stroke: '#16a34a' },
  Medium:     { stroke: '#d97706' },
  Low:        { stroke: '#dc2626' },
  Unverified: { stroke: '#94a3b8', strokeDasharray: '5 5' },
};

const EDGE_LABEL: Record<string, string> = {
  High: '✅ Confirmed', Medium: '⚠️ Medium', Low: '❓ Low', Unverified: 'Unverified',
};

/** Convert a saved DB edge to a ReactFlow edge */
function dbEdgeToFlow(e: GraphEdgeDto): Edge {
  return {
    id: e.edgeId,
    source: e.sourceDatabaseId,
    target: e.targetDatabaseId,
    label: EDGE_LABEL[e.confidence] ?? e.confidence,
    data: { confidence: e.confidence, protocol: e.protocol, direction: e.direction, saved: true },
    style: EDGE_STYLE[e.confidence] ?? EDGE_STYLE.Unverified,
    markerEnd: { type: MarkerType.ArrowClosed },
  };
}

export default function CommunicationMap() {
  const qc = useQueryClient();
  const [selectedProject, setSelectedProject] = useState('');
  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);
  const [selectedEdge, setSelectedEdge] = useState<Edge | null>(null);
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle');

  const projects = useQuery({ queryKey: ['projects'], queryFn: getProjects });
  const databases = useQuery({
    queryKey: ['databases', selectedProject],
    queryFn: () => getDatabases(selectedProject),
    enabled: !!selectedProject,
  });
  const savedEdges = useQuery({
    queryKey: ['graphEdges', selectedProject],
    queryFn: () => getGraphEdges(selectedProject),
    enabled: !!selectedProject,
  });

  const saveMutation = useMutation({
    mutationFn: (edgeList: Edge[]) =>
      saveGraphEdges(
        selectedProject,
        edgeList.map(e => ({
          edgeId: e.id,
          sourceDatabaseId: e.source,
          targetDatabaseId: e.target,
          confidence: e.data?.confidence ?? 'Unverified',
          protocol: e.data?.protocol ?? 'Unknown',
          direction: e.data?.direction ?? 'Bidirectional',
        }))
      ),
    onSuccess: () => {
      setSaveStatus('saved');
      qc.invalidateQueries({ queryKey: ['graphEdges', selectedProject] });
      setTimeout(() => setSaveStatus('idle'), 2000);
    },
    onError: () => setSaveStatus('error'),
  });

  const deleteEdgeMutation = useMutation({
    mutationFn: deleteGraphEdge,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['graphEdges', selectedProject] }),
  });

  // Build nodes whenever databases load
  const buildGraph = useCallback(() => {
    if (!databases.data) return;
    const cols = Math.ceil(Math.sqrt(databases.data.length));
    const built: Node[] = databases.data.map((db, i) => ({
      id: db.databaseId,
      position: { x: (i % cols) * 240, y: Math.floor(i / cols) * 170 },
      data: {
        label: (
          <div style={{ textAlign: 'center' }}>
            <div style={{ fontSize: 11, fontWeight: 700, color: ENGINE_COLOR[db.engine] ?? '#94a3b8' }}>
              {db.engine}
            </div>
            <div style={{ fontSize: 13, fontWeight: 600 }}>{db.name}</div>
            {db.hostName && <div style={{ fontSize: 10, color: '#94a3b8' }}>{db.hostName}</div>}
          </div>
        ),
        engine: db.engine,
      },
      style: {
        background: '#fff', border: `2px solid ${ENGINE_COLOR[db.engine] ?? '#94a3b8'}`,
        borderRadius: 10, padding: '10px 14px', minWidth: 140, fontSize: 13,
      },
    }));
    setNodes(built);

    // Restore saved edges from DB
    if (savedEdges.data?.length) {
      setEdges(savedEdges.data.map(dbEdgeToFlow));
    } else {
      setEdges([]);
    }
  }, [databases.data, savedEdges.data, setNodes, setEdges]);

  // When saved edges load (after graph already built), patch them in
  useEffect(() => {
    if (savedEdges.data && nodes.length > 0) {
      setEdges(savedEdges.data.map(dbEdgeToFlow));
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [savedEdges.data]);

  const onConnect = useCallback((connection: Connection) => {
    const edge: Edge = {
      id: crypto.randomUUID(),
      source: connection.source ?? '',
      target: connection.target ?? '',
      sourceHandle: connection.sourceHandle,
      targetHandle: connection.targetHandle,
      label: EDGE_LABEL.Unverified,
      data: { confidence: 'Unverified', protocol: 'Unknown', direction: 'Bidirectional', saved: false },
      style: EDGE_STYLE.Unverified,
      markerEnd: { type: MarkerType.ArrowClosed },
    };
    setEdges(eds => addEdge(edge, eds));
  }, [setEdges]);

  const confirmEdge = () => {
    if (!selectedEdge) return;
    setEdges(eds => eds.map(e =>
      e.id === selectedEdge.id
        ? { ...e, data: { ...e.data, confidence: 'High' }, style: EDGE_STYLE.High, label: EDGE_LABEL.High }
        : e
    ));
    setSelectedEdge(null);
  };

  const rejectEdge = () => {
    if (!selectedEdge) return;
    // If it was persisted, delete from DB too
    if (selectedEdge.data?.saved) deleteEdgeMutation.mutate(selectedEdge.id);
    setEdges(eds => eds.filter(e => e.id !== selectedEdge.id));
    setSelectedEdge(null);
  };

  const handleSaveMap = () => {
    setSaveStatus('saving');
    saveMutation.mutate(edges);
  };

  const confirmedCount  = edges.filter(e => e.data?.confidence === 'High').length;
  const unverifiedCount = edges.filter(e => e.data?.confidence === 'Unverified').length;

  return (
    <div>
      <div className="page-header">
        <h2>Communication Map</h2>
        {nodes.length > 0 && (
          <button
            className="btn btn-primary"
            onClick={handleSaveMap}
            disabled={saveStatus === 'saving' || edges.length === 0}
          >
            {saveStatus === 'saving' ? 'Saving…' : saveStatus === 'saved' ? '✓ Saved' : 'Save Map'}
          </button>
        )}
      </div>

      {saveStatus === 'error' && (
        <div className="error-msg" style={{ marginBottom: 16 }}>Failed to save edges. Please try again.</div>
      )}

      <div className="card" style={{ padding: '14px 20px', marginBottom: 20 }}>
        <div style={{ display: 'flex', gap: 14, alignItems: 'flex-end' }}>
          <div className="form-row" style={{ marginBottom: 0, minWidth: 240 }}>
            <label>Project</label>
            <select value={selectedProject} onChange={e => { setSelectedProject(e.target.value); setNodes([]); setEdges([]); }}>
              <option value="">Choose a project…</option>
              {projects.data?.map(p => <option key={p.projectId} value={p.projectId}>{p.name}</option>)}
            </select>
          </div>
          <button className="btn btn-primary" disabled={!databases.data?.length} onClick={buildGraph}>
            Build Graph
          </button>
          <span style={{ fontSize: 12, color: '#94a3b8' }}>
            Drag between nodes to add flows. Click an edge to confirm or reject.
            {savedEdges.data?.length ? ` ${savedEdges.data.length} edge(s) saved.` : ''}
          </span>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 16 }}>
        <div className="card" style={{ flex: 1, padding: 0, height: 520, overflow: 'hidden' }}>
          {nodes.length === 0 ? (
            <div className="empty-state" style={{ paddingTop: 80 }}>
              <div className="empty-state-icon">🕸️</div>
              <p>Select a project and click <strong>Build Graph</strong> to start mapping.</p>
            </div>
          ) : (
            <ReactFlow
              nodes={nodes} edges={edges}
              onNodesChange={onNodesChange} onEdgesChange={onEdgesChange}
              onConnect={onConnect}
              onEdgeClick={(_, edge) => setSelectedEdge(edge)}
              fitView
            >
              <Background />
              <Controls />
              <MiniMap nodeColor={n => ENGINE_COLOR[n.data?.engine] ?? '#94a3b8'} />
            </ReactFlow>
          )}
        </div>

        <div style={{ width: 260 }}>
          {selectedEdge ? (
            <div className="card">
              <div className="card-title">Selected Edge</div>
              <div style={{ fontSize: 13, marginBottom: 8, display: 'flex', flexDirection: 'column', gap: 4 }}>
                <div><strong>From:</strong> {selectedEdge.source.slice(0, 8)}…</div>
                <div><strong>To:</strong>   {selectedEdge.target.slice(0, 8)}…</div>
                <div><strong>Confidence:</strong> {CONFIDENCE_LABEL[selectedEdge.data?.confidence]} {selectedEdge.data?.confidence}</div>
                <div><strong>Protocol:</strong> {selectedEdge.data?.protocol}</div>
                {selectedEdge.data?.saved && <span className="badge badge-green" style={{ alignSelf: 'flex-start', marginTop: 4 }}>Persisted</span>}
              </div>
              <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
                <button className="btn btn-primary" style={{ flex: 1, fontSize: 12 }} onClick={confirmEdge}>
                  Confirm
                </button>
                <button className="btn btn-danger" style={{ flex: 1, fontSize: 12 }} onClick={rejectEdge}>
                  Reject
                </button>
              </div>
            </div>
          ) : (
            <div className="card">
              <div className="card-title">Legend</div>
              {Object.entries(ENGINE_COLOR).map(([engine, color]) => (
                <div key={engine} style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6, fontSize: 13 }}>
                  <div style={{ width: 12, height: 12, borderRadius: 3, background: color }} />
                  {engine}
                </div>
              ))}
              <hr style={{ margin: '12px 0', borderColor: '#e2e8f0' }} />
              <div style={{ fontSize: 12, color: '#94a3b8', display: 'flex', flexDirection: 'column', gap: 3 }}>
                <div>✅ Confirmed (green)</div>
                <div>⚠️ Medium (amber)</div>
                <div>🔵 Unverified (dashed)</div>
              </div>
            </div>
          )}

          <div className="card" style={{ marginTop: 0 }}>
            <div className="card-title">Edge Summary</div>
            <div style={{ fontSize: 13, display: 'flex', flexDirection: 'column', gap: 4 }}>
              <div>Total flows: <strong>{edges.length}</strong></div>
              <div>Confirmed: <strong style={{ color: '#16a34a' }}>{confirmedCount}</strong></div>
              <div>Unverified: <strong style={{ color: '#94a3b8' }}>{unverifiedCount}</strong></div>
              <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                Click <strong>Save Map</strong> to persist all edges.
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
