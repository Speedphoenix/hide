package hide.view.l3d;
using Lambda;

import hxd.Math;
import hxd.Key as K;

import hide.prefab.Prefab as PrefabElement;
import hide.prefab.Object3D;
import hide.prefab.l3d.Instance;
import hide.prefab.l3d.Layer;
import h3d.scene.Object;


class LevelEditContext extends hide.prefab.EditContext {
	public var parent : Level3D;
	public function new(parent, context) {
		super(context);
		this.parent = parent;
	}
}

@:access(hide.view.l3d.Level3D)
class CamController extends h3d.scene.CameraController {
	var level3d : Level3D;

	public function new(parent, level3d) {
		super(null, parent);
		this.level3d = level3d;
	}

	override function onEvent( e : hxd.Event ) {
		switch( e.kind ) {
		case EWheel:
			zoom(e.wheelDelta);
		case EPush:
			@:privateAccess scene.events.startDrag(onEvent, function() pushing = -1, e);
			pushing = e.button;
			pushX = e.relX;
			pushY = e.relY;
		case ERelease, EReleaseOutside:
			if( pushing == e.button ) {
				pushing = -1;
				@:privateAccess scene.events.stopDrag();
			}
		case EMove:
			switch( pushing ) {
			case 1:
				var m = 0.001 * curPos.x * panSpeed / 25;
				if(hxd.Key.isDown(hxd.Key.SHIFT)) {
					pan(-(e.relX - pushX) * m, (e.relY - pushY) * m);
				}
				else {
					var se = level3d.sceneEditor;
					var fromPt = se.screenToWorld(pushX, pushY);
					var toPt = se.screenToWorld(e.relX, e.relY);
					var delta = toPt.sub(fromPt).toVector();
					delta.w = 0;
					targetOffset = targetOffset.sub(delta);
				}
				pushX = e.relX;
				pushY = e.relY;
			case 2:
				rot(e.relX - pushX, e.relY - pushY);
				pushX = e.relX;
				pushY = e.relY;
			default:
			}
		default:
		}
	}
}

@:access(hide.view.l3d.Level3D)
private class Level3DSceneEditor extends hide.comp.SceneEditor {
	var parent : Level3D;

	public function new(view, data) {
		super(view, data);
		parent = cast view;
		this.localTransform = false; // TODO: Expose option
	}

	override function makeCamController() {
		var c = new CamController(scene.s3d, parent);
		c.friction = 0.9;
		c.panSpeed = 0.6;
		c.zoomAmount = 1.05;
		c.smooth = 0.7;
		return c;
	}

	override function refresh(?callback) {
		parent.onRefresh();
		super.refresh(callback);
	}

	override function refreshScene() {
		super.refreshScene();
		parent.onRefreshScene();
	}

	override function update(dt) {
		super.update(dt);
		parent.onUpdate(dt);
	}

	override function onSceneReady() {
		super.onSceneReady();
		parent.onSceneReady();
	}

	override function selectAll() {
		var all = [for(e in getAllSelectable()) if(e.to(Layer) == null) e];
		selectObjects(all);
	}

	override function updateTreeStyle(p: PrefabElement, el: Element) {
		super.updateTreeStyle(p, el);
		parent.updateTreeStyle(p, el);
	}

	override function onPrefabChange(p: PrefabElement, ?pname: String) {
		super.onPrefabChange(p, pname);
		parent.onPrefabChange(p, pname);
	}

	override function projectToGround(ray: h3d.col.Ray) {
		var polygons = parent.getGroundPolys();
		var minDist = -1.;
		for(polygon in polygons) {
			var ctx = getContext(polygon);
			var mesh = Std.instance(ctx.local3d, h3d.scene.Mesh);
			if(mesh == null)
				continue;
			var collider = mesh.getGlobalCollider();
			var d = collider.rayIntersection(ray, true);
			if(d > 0 && (d < minDist || minDist < 0)) {
				minDist = d;
			}
		}
		if(minDist >= 0)
			return minDist;
		return super.projectToGround(ray);
	}

	override function getNewContextMenu(current: PrefabElement) {
		var newItems = new Array<hide.comp.ContextMenu.ContextMenuItem>();

		if(current != null && current.type == "object" && current.name == "settings" && current.parent == sceneData)
			newItems.push(getNewTypeMenuItem("renderProps",current)); // hack : todo

		function setup(p : PrefabElement) {
			var proj = screenToWorld(scene.s2d.width/2, scene.s2d.height/2);
			var obj3d = p.to(hide.prefab.Object3D);
			if(proj != null && obj3d != null && p.to(hide.prefab.l3d.Layer) == null) {
				var parentMat = worldMat(getObject(p.parent));
				parentMat.invert();
				var localMat = new h3d.Matrix();
				localMat.initTranslation(proj.x, proj.y, proj.z);
				localMat.multiply(localMat, parentMat);
				obj3d.setTransform(localMat);
			}

			autoName(p);
			haxe.Timer.delay(addObject.bind(p), 0);
		}

		newItems = newItems.concat(super.getNewContextMenu(current));

		function addNewInstances() {
			var types = Level3D.getCdbTypes();
			var items = new Array<hide.comp.ContextMenu.ContextMenuItem>();
			for(type in types) {
				var typeId = type.name.split("@").pop();
				var label = typeId.charAt(0).toUpperCase() + typeId.substr(1);

				var refCol = Instance.findRefColumn(type);
				if(refCol == null)
					continue;
				var refSheet = type.base.getSheet(refCol.sheet);
				var idCol = Instance.findIDColumn(refSheet);

				function make(name) {
					var p = new hide.prefab.l3d.Instance(current);
					p.props = type.getDefaults();
					Reflect.setField(p.props, "$cdbtype", typeId);
					p.name = name;
					setup(p);
					return p;
				}

				if(idCol != null) {
					var kindItems = new Array<hide.comp.ContextMenu.ContextMenuItem>();
					for(line in refSheet.lines) {
						var kind : String = Reflect.getProperty(line, idCol.name);
						kindItems.push({
							label : kind,
							click : function() {
								var p = make(kind.charAt(0).toLowerCase() + kind.substr(1));
								Reflect.setField(p.props, refCol.col.name, kind);
							}
						});
					}
					items.unshift({
						label : label,
						menu: kindItems
					});
				}
				else {
					items.push({
						label : label,
						click : make.bind(typeId)
					});
				}
			}
			newItems.unshift({
				label : "Instance",
				menu: items
			});
		};
		addNewInstances();
		return newItems;
	}

	override function fillProps(edit:hide.prefab.EditContext, e:PrefabElement) {
		super.fillProps(edit, e);

		var sheet = Level3D.getCdbModel(e);
		var group = new hide.Element('
			<div class="group" name="CDB">
				<dl><dt>Type</dt><dd><select><option value="">-- Choose --</option></select></dd>
			</div>
		');

		var select = group.find("select");
		var cdbTypes = Level3D.getCdbTypes();
		for(t in cdbTypes) {
			var current = sheet != null && sheet.name == t.name;
			var id = t.name.split("@").pop();
			var opt = new hide.Element("<option>").attr("value", id).text(id).appendTo(select);
		}
		if(sheet != null) {
			select.val(sheet.name.split("@").pop());
		}
		select.change(function(v) {
			var typeId = select.val();
			var cdbSheet = Level3D.resolveCdbType(typeId);
			if(cdbSheet == null)
				return;

			properties.undo.change(Field(e, "props", e.props), ()->edit.rebuildProperties());
			e.props = cdbSheet.getDefaults();
			Reflect.setField(e.props, "$cdbtype", typeId);
			edit.onChange(e, "props");
			edit.rebuildProperties();
		});

		edit.properties.add(group);

		if(sheet != null) {
			var props = new hide.Element('<div></div>').appendTo(group.find(".content"));
			var editor = new hide.comp.cdb.ObjEditor(sheet, e.props, props);
			editor.undo = properties.undo;
			editor.onChange = function(pname) {
				edit.onChange(e, 'props.$pname');
			}
		}
	}
}

class Level3D extends FileView {

	public var sceneEditor : Level3DSceneEditor;
	var data : hide.prefab.l3d.Level3D;
	var tabs : hide.comp.Tabs;

	var tools : hide.comp.Toolbar;

	var levelProps : hide.comp.PropsEditor;

	var layerToolbar : hide.comp.Toolbar;
	var layerButtons : Map<PrefabElement, hide.comp.Toolbar.ToolToggle>;

	var grid : h3d.scene.Graphics;
	var showGrid = true;
	var autoSync : Bool;
	var currentVersion : Int = 0;
	var lastSyncChange : Float = 0.;
	var currentSign : String;
	var typeColorMap : Map<String, String>;

	var scene(get, null):  hide.comp.Scene;
	function get_scene() return sceneEditor.scene;
	public var properties(get, null):  hide.comp.PropsEditor;
	function get_properties() return sceneEditor.properties;

	override function onDisplay() {
		saveDisplayKey = "Level3D:" + getPath().split("\\").join("/").substr(0,-1);
		data = new hide.prefab.l3d.Level3D();
		var content = sys.io.File.getContent(getPath());
		data.load(haxe.Json.parse(content));
		currentSign = haxe.crypto.Md5.encode(content);

		// typeColorMap = new Map();
		// var colors = ide.currentProps.get("l3d.colors");
		// if(colors != null) {
		// 	for(f in Reflect.fields(colors)) {
		// 		var col = Reflect.field(color, f);

		// 	}
		// }
		

		element.html('
			<div class="flex vertical">
				<div class="toolbar">
					<span class="tools-buttons"></span>
					<span class="layer-buttons"></span>
				</div>
				<div class="flex">
					<div class="scene">
					</div>
					<div class="tabs">
						<div class="tab" name="Scene" icon="sitemap">
							<div class="hide-block" style="height:60%">
								<div class="hide-scene-tree hide-list">
								</div>
							</div>
							<div class="hide-scroll"></div>
						</div>
						<div class="tab" name="Properties" icon="cog">
							<div class="level-props"></div>
						</div>
					</div>
				</div>
			</div>
		');
		tools = new hide.comp.Toolbar(null,element.find(".tools-buttons"));
		layerToolbar = new hide.comp.Toolbar(null,element.find(".layer-buttons"));
		tabs = new hide.comp.Tabs(null,element.find(".tabs"));
		currentVersion = undo.currentID;

		levelProps = new hide.comp.PropsEditor(undo,null,element.find(".level-props"));
		sceneEditor = new Level3DSceneEditor(this, data);
		sceneEditor.addSearchBox(element.find(".hide-scene-tree").first());
		element.find(".hide-scene-tree").first().append(sceneEditor.tree.element);
		element.find(".hide-scroll").first().append(sceneEditor.properties.element);
		element.find(".scene").first().append(sceneEditor.scene.element);
		sceneEditor.tree.element.addClass("small");

		// Level edit
		{
			var edit = new LevelEditContext(this, sceneEditor.context);
			edit.prefabPath = state.path;
			edit.properties = levelProps;
			edit.scene = sceneEditor.scene;
			edit.cleanups = [];
			data.edit(edit);
		}
	}

	public function onSceneReady() {

		tools.saveDisplayKey = "Level3D/toolbar";
		tools.addButton("video-camera", "Perspective camera", () -> resetCamera(false));
		tools.addButton("video-camera", "Top camera", () -> resetCamera(true)).find(".icon").css({transform: "rotateZ(90deg)"});
		tools.addToggle("anchor", "Snap to ground", (v) -> sceneEditor.snapToGround = v, sceneEditor.snapToGround);
		tools.addToggle("compass", "Local transforms", (v) -> sceneEditor.localTransform = v, sceneEditor.localTransform);
		tools.addToggle("th", "Show grid", function(v) { showGrid = v; updateGrid(); }, showGrid);
		tools.addButton("sun-o", "Bake Lights", () -> bakeLights());
		tools.addButton("map", "Bake Volumetric Lightmaps", () -> { bakeLights(); bakeVolumetricLightmaps(); });

		tools.addColor("Background color", function(v) {
			scene.engine.backgroundColor = v;
			updateGrid();
		}, scene.engine.backgroundColor);

		tools.addToggle("refresh", "Auto save", function(b) {
			autoSync = b;
		});

		updateGrid();
	}

	function bakeLights() {
		var curSel = sceneEditor.curEdit.elements;
		sceneEditor.selectObjects([]);
		var passes = [];
		for( m in scene.s3d.getMaterials() ) {
			var s = m.getPass("shadow");
			if( s != null && !s.isStatic ) passes.push(s);
		}
		for( p in passes )
			p.isStatic = true;
		scene.s3d.computeStatic();
		for( p in passes )
			p.isStatic = false;
		var lights = data.getAll(hide.prefab.Light);
		for( l in lights )
			l.saveBaked(sceneEditor.context);
		sceneEditor.selectObjects(curSel);
	}

	function bakeVolumetricLightmaps(){
		var volumetricLightmaps = data.getAll(hide.prefab.l3d.VolumetricLightmap);
		var total = 0;
		for( v in volumetricLightmaps )
			total += v.volumetricLightmap.getProbeCount();
		if( total == 0 )
			return;
		if( !ide.confirm("Bake "+total+" probes?") )
			return;
		function bakeNext() {
			var v = volumetricLightmaps.shift();
			if( v == null ) {
				ide.message("Done");
				return;
			}
			v.startBake(sceneEditor.curEdit, bakeNext);
			sceneEditor.selectObjects([v]);
		}
		bakeNext();
	}

	function resetCamera( top : Bool ) {
		var targetPt = new h3d.col.Point(0, 0, 0);
		var curEdit = sceneEditor.curEdit;
		if(curEdit != null && curEdit.rootObjects.length > 0) {
			targetPt = curEdit.rootObjects[0].getAbsPos().getPosition().toPoint();
		}
		if(top)
			sceneEditor.cameraController.set(200, Math.PI/2, 0.001, targetPt);
		else
			sceneEditor.cameraController.set(200, -4.7, 0.8, targetPt);
		sceneEditor.cameraController.toTarget();
	}

	override function getDefaultContent() {
		return haxe.io.Bytes.ofString(ide.toJSON(new hide.prefab.l3d.Level3D().save()));
	}

	override function onFileChanged(wasDeleted:Bool) {
		if( !wasDeleted ) {
			// double check if content has changed
			var content = sys.io.File.getContent(getPath());
			var sign = haxe.crypto.Md5.encode(content);
			if( sign == currentSign )
				return;
		}
		super.onFileChanged(wasDeleted);
	}

	override function save() {
		var content = ide.toJSON(data.save());
		currentSign = haxe.crypto.Md5.encode(content);
		sys.io.File.saveContent(getPath(), content);
	}

	function updateGrid() {
		if(grid != null) {
			grid.remove();
			grid = null;
		}

		if(!showGrid)
			return;

		grid = new h3d.scene.Graphics(scene.s3d);
		grid.scale(1);
		grid.material.mainPass.setPassName("debuggeom");

		var col = h3d.Vector.fromColor(scene.engine.backgroundColor);
		var hsl = col.toColorHSL();
		if(hsl.z > 0.5) hsl.z -= 0.1;
		else hsl.z += 0.1;
		col.makeColor(hsl.x, hsl.y, hsl.z);

		grid.lineStyle(1.0, col.toColor(), 1.0);
		for(ix in 0...data.width+1) {
			grid.moveTo(ix, 0, 0);
			grid.lineTo(ix, data.height, 0);
		}
		for(iy in 0...data.height+1) {
			grid.moveTo(0, iy, 0);
			grid.lineTo(data.width, iy, 0);
		}
		grid.lineStyle(0);
	}

	function onUpdate(dt:Float) {
		var cam = scene.s3d.camera;
		if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
			save();
			lastSyncChange = properties.lastChange;
			currentVersion = undo.currentID;
		}
	}

	function onRefresh() {
		refreshLayerIcons();
	}

	function onRefreshScene() {
		var all = data.flatten(hxd.prefab.Prefab);
		for(elt in all)
			refreshSceneStyle(elt);

		// Apply first render props
		var settings = data.children.find(c -> c.name == "settings");
		if(settings != null) {
			for(c in settings.children) {
				var renderProps = c.to(hide.prefab.RenderProps);
				if(renderProps != null) {
					renderProps.applyProps(scene.s3d.renderer);
					break;
				}
			}
		}
	}

	override function onDragDrop(items : Array<String>, isDrop : Bool) {
		var supported = ["fbx", "fx"];
		var paths = [];
		for(path in items) {
			var ext = haxe.io.Path.extension(path).toLowerCase();
			if(supported.indexOf(ext) >= 0) {
				paths.push(path);
			}
		}
		if(paths.length > 0) {
			if(isDrop) {
				var curSel = sceneEditor.getSelection();
				var parent : PrefabElement = data;
				if(curSel.length > 0) {
					var sel = curSel[0];
					if(Type.getClass(sel) == Object3D)
						parent = sel;
					else if(sel.parent != null && Type.getClass(sel.parent) == Object3D)
						parent = sel.parent;
					else {
						var curLayer = sel.to(Layer);
						if(curLayer == null)
							curLayer = sel.getParent(Layer);
						if(curLayer != null)
							parent = curLayer;
					}
				}
				sceneEditor.dropObjects(paths, parent);
			}
			return true;
		}
		return false;
	}

	function refreshLayerIcons() {
		if(layerButtons != null) {
			for(b in layerButtons)
				b.element.remove();
		}
		layerButtons = new Map<PrefabElement, hide.comp.Toolbar.ToolToggle>();
		var all = data.flatten(hxd.prefab.Prefab);
		var initDone = false;
		for(elt in all) {
			var layer = elt.to(hide.prefab.l3d.Layer);
			if(layer == null) continue;
			layerButtons[elt] = layerToolbar.addToggle("file", layer.name, layer.name, function(on) {
				if(initDone)
					sceneEditor.setVisible([layer], on);
			}, layer.visible);

			refreshLayerIcon(layer);
		}
		initDone = true;
	}

	function refreshLayerIcon(layer: hide.prefab.l3d.Layer) {
		// var lb = layerButtons[layer];
		// if(lb != null) {
		// 	var color = "#" + StringTools.hex(layer.color & 0xffffff, 6);
		// 	if(layer.visible != lb.isDown())
		// 		lb.toggle(layer.visible);
		// 	lb.element.find(".icon").css("color", color);
		// 	var label = lb.element.find("label");
		// 	if(layer.locked)
		// 		label.addClass("locked");
		// 	else
		// 		label.removeClass("locked");
		// }
	}


	function updateTreeStyle(p: PrefabElement, el: Element) {
		var styles = ide.currentProps.get("l3d.treeStyles");
		var style: Dynamic = null;
		var typeId = getCdbTypeId(p);
		if(typeId != null) {
			style = Reflect.field(styles, typeId);
		}
		if(style == null) {
			style = Reflect.field(styles, p.name);
		}
		var a = el.find("a").first();
		if(style == null)
			a.removeAttr("style");
		else
			a.css(style);
	}

	function onPrefabChange(p: PrefabElement, ?pname: String) {
		refreshSceneStyle(p);
	}

	function refreshSceneStyle(p: PrefabElement) {
		var level3d = p.to(hide.prefab.l3d.Level3D);
		if(level3d != null) {
			updateGrid();
			return;
		}
		// var layer = p.to(hide.prefab.l3d.Layer);
		// if(layer != null)
		// 	applyLayerProps(layer);

		var color = getDisplayColor(p);
		if(color == null)
			color = 0x80ffffff;
		else
			color = (color & 0xffffff) | 0xa0000000;

		var box = p.to(hide.prefab.Box);
		if(box != null) {
			var ctx = sceneEditor.getContext(box);
			box.setColor(ctx, color);
		}
		var poly = p.to(hide.prefab.l3d.Polygon);
		if(poly != null) {
			var ctx = sceneEditor.getContext(poly);
			poly.setColor(ctx, color);
		}
	}

	function applyLayerProps(layer: hide.prefab.l3d.Layer) {
		var obj3ds = layer.getAll(hide.prefab.Object3D);
		for(obj in obj3ds) {
			var i = @:privateAccess sceneEditor.interactives.get(obj);
			if(i != null) i.visible = !layer.locked;
		}
		for(box in layer.getAll(hide.prefab.Box)) {
			var ctx = sceneEditor.getContext(box);
			box.setColor(ctx, getDisplayColor(box));
		}
		for(poly in layer.getAll(hide.prefab.l3d.Polygon)) {
			var ctx = sceneEditor.getContext(poly);
			poly.updateInstance(ctx);
		}
	}

	function getDisplayColor(p: PrefabElement) : Null<Int> {
		var typeId = getCdbTypeId(p);
		if(typeId != null) {
			var colors = ide.currentProps.get("l3d.colors");
			var color = Reflect.field(colors, typeId);
			if(color != null) {
				return Std.parseInt("0x"+color.substr(1)) | 0xff000000;
			}
		}
		return null;
	}

	public static function getLevelSheet() {
		return Ide.inst.database.getSheet(Ide.inst.currentProps.get("l3d.cdbLevel", "level"));
	}

	static function resolveCdbType(id: String) {
		var types = Level3D.getCdbTypes();
		return types.find(t -> t.name.split("@").pop() == id);
	}

	public static function getCdbTypes() {
		var levelSheet = getLevelSheet();
		if(levelSheet == null) return [];
		return [for(c in levelSheet.columns) if(c.type == TList) levelSheet.getSub(c)];
	}

	public static function getCdbTypeId(p: PrefabElement) : String {
		if(p.props == null)
			return null;
		return Reflect.getProperty(p.props, "$cdbtype");
	}

	public static function getCdbModel(e:hxd.prefab.Prefab):cdb.Sheet {
		var typeName : String = getCdbTypeId(e);
		if(typeName == null)
			return null;
		return resolveCdbType(typeName);
	}

	function getGroundPolys() {
		var gname = props.get("l3d.groundLayer");
		var groundLayer = data.getOpt(Layer, gname);
		if(groundLayer == null)
			return [];
		var polygons = groundLayer.getAll(hide.prefab.l3d.Polygon);
		return polygons;
	}

	static var _ = FileTree.registerExtension(Level3D,["l3d"],{ icon : "sitemap", createNew : "Level3D" });
}