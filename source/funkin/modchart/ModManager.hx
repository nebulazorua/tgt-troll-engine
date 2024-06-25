package funkin.modchart;
// @author Nebula_Zorua

import flixel.tweens.FlxEase.EaseFunction;
import funkin.modchart.Modifier.RenderInfo;
import flixel.math.FlxPoint;
import flixel.tweens.FlxEase;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.FlxSprite;
import flixel.FlxG;
import math.Vector3;
import funkin.modchart.Modifier.ModifierType;
import funkin.modchart.modifiers.*;
import funkin.modchart.events.*;
import funkin.objects.playfields.NoteField;

// Weird amalgamation of Schmovin' modifier system, Andromeda modifier system and my own new shit -neb
// NEW: Now also has some features of mirin (aliases, nodes)


/**
 * So, what is a Node?
 * A Node can be used to extend or otherwise modify modifiers
 * (for example you can have a screen bounce aux mod + node w/ that aux mod as an input, and then change transformX)
 */
typedef Node = {
	var lastIndex:Int; // to make sure it doesnt get hit multiple times per update
    var in_mods:Array<String>; /// the modifiers that get input into this node
    var out_mods:Array<String>; // the modifiers that get transformed by this node
	var nodeFunc:(Array<Float>, Int)->Dynamic; // takes an array of the input mods' values, and returns an array of transformed modifier values, if out_mods.length > 0
}

class ModManager {
	public function new(state:PlayState) {
        this.state=state;
    }

	public function registerAux(name:String)
		return quickRegister(new SubModifier(name, this));
    
	public function registerDefaultModifiers()
	{
		var quickRegs:Array<Any> = [
			ReverseModifier,
			SwapModifier,
			DrunkModifier,
			BeatModifier,
			AlphaModifier,
			ScaleModifier, 
			ConfusionModifier, 
			OpponentModifier, 
			TransformModifier, 
			// InfinitePathModifier,  // broken
			PathModifier,
			AccelModifier,
			PerspectiveModifier,
			ZoomModifier
		];
		for (mod in quickRegs)
			quickRegister(Type.createInstance(mod, [this]));

		quickRegister(new RotateModifier(this));
		quickRegister(new RotateModifier(this, 'center', new Vector3(FlxG.width* 0.5, FlxG.height* 0.5)));
		quickRegister(new LocalRotateModifier(this, 'local'));

		registerAux("noteSpawnTime");
		registerAux("drawDistance");
		registerAux("disableDrawDistMult");
		registerAux("flashR");
		registerAux("flashG");
		registerAux("flashB");
		registerAux("xmod");
		registerAux("cmod");
		registerAux("movePastReceptors");
		for (i in 0...4){
			registerAux("xmod" + i);
			registerAux("cmod" + i);
			registerAux("noteSpawnTime" + i);
		}

		for (playerNumber => mods in activeMods){
			setDefaultValues(playerNumber);
			updateActiveMods(playerNumber);
        }

	}

	function setDefaultValues(mN:Int=-1){
/* 		for(modName => mod in register){
			setValue(modName, 0, mN);
        } */
		
		for (i in 0...4)
			setValue("noteSpawnTime" + i, 0, mN);
		
		setValue("noteSpawnTime", 0, mN); // when this is <= 0, it defaults to field.spawnTime
		setValue("drawDistance", FlxG.height * 1.1, mN); // MAY NOT REPRESENT ACTUAL DRAWDISTANCE: drawDistance is modified by the notefields aswell
		// so whAT you set drawDistance to might be lower or higher than expected because of the draw distance mult. setting
		// If you want to disable the usage of draw distance muitiplier, you can set 'disableDrawDistMult' to anything but 0
		setValue("xmod", 1, mN);
		setValue("cmod", -1, mN);
		setValue("scale", 1, mN);
		setValue("scaleX", 1, mN);
		setValue("scaleY", 1, mN);
		for (i in 0...4){
			setValue('cmod$i', -1, mN);
			setValue('xmod$i', 1, mN);
			setValue('scale${i}', 1, mN);
			setValue('scale${i}X', 1, mN);
			setValue('scale${i}Y', 1, mN);
		}
		setValue("movePastReceptors", 0);
		setValue("flashR", 1, mN);
		setValue("flashG", 1, mN);
		setValue("flashB", 1, mN);
	}


	private var state:PlayState;

	public var timeline:EventTimeline = new EventTimeline();

	var notemodRegister:Map<String, Modifier> = [];
	var miscmodRegister:Map<String, Modifier> = [];

	public var register:Map<String, Modifier> = [];

	var activeMods:Array<Array<String>> = [[], []]; // mods that should be executing and will be called by functions like getPos
	// ^^ maybe this can be seperated into a misc and note one, just so you arent checking misc mods for note shit & vice versa
	// also so you arent calling shit like getPos on submods etc etc, might be better for optimization to do that
	var modArray:Array<Modifier> = [];
	var aliases:Map<String, String> = [];

	var nodes:Map<String, Array<Node>> = []; // maps nodes by their inputs
	var nodeArray:Array<Node> = [];

	var touchedMods:Array<Array<String>> = [[], []];
	var nodeIndex:Int = 0;

    inline public function quickRegister(mod:Modifier)
        registerMod(mod.getName(), mod);

    public function registerAlias(alias:String, mod:String)
		aliases.set(alias, mod);

    public function registerNode(node:Node){
        var inputs = node.in_mods;
		for(inp in inputs){
            if(!nodes.exists(inp))
                nodes.set(inp, []);
            
            nodes.get(inp).push(node);
        }
		nodeArray.push(node);
    }

	public function quickNode(inputs:Array<String>, nodeFunc:(Array<Dynamic>, Int) -> Dynamic, ?outputs:Array<String>){
		if (outputs == null)
			outputs=[];
		registerNode({
			lastIndex: -1,
			in_mods: inputs,
			out_mods: outputs,
			nodeFunc: nodeFunc
		});
    }

    function getActualModName(m:String)
		return aliases.exists(m) ? aliases.get(m) : m;

    public function registerMod(modName:String, mod:Modifier, ?registerSubmods = true){
        register.set(modName, mod);
		switch (mod.getModType()){
			case NOTE_MOD:
				notemodRegister.set(modName, mod);
			case MISC_MOD:
				miscmodRegister.set(modName, mod);
		}

		timeline.addMod(modName);
		modArray.push(mod);
        
        for(a => m in mod.getAliases())
            registerAlias(a, m);
        

		if (registerSubmods){
			for (name in mod.submods.keys())
			{
				var submod = mod.submods.get(name);
				quickRegister(submod);
			}
        }

		setValue(modName, 0); // so if it should execute it gets added Automagically
		modArray.sort((a, b) -> Std.int(a.getOrder() - b.getOrder()));

    }

	public function addHScriptModifier(modName:String, ?defaultVal:Float = 0):Null<HScriptModifier>
	{	
		var modifier = HScriptModifier.fromName(this, null, modName);
		if (modifier == null) return null;
	
		quickRegister(modifier);
		setValue(modifier.getName(), defaultVal==null ? 0 : defaultVal);
		
		return modifier;
	}

    inline public function get(modName:String)
		return register.get(getActualModName(modName));
    
	inline public function getPercent(modName:String, player:Int)
		return !register.exists(getActualModName(modName))?0:get(modName).getPercent(player);

	inline public function getValue(modName:String, player:Int)
		return !register.exists(getActualModName(modName))?0:get(modName).getValue(player);

    inline public function setPercent(modName:String, val:Float, player:Int=-1)
		setValue(modName, val/100, player);

	inline public function setCurrentPercent(modName:String, val:Float, player:Int = -1)
		setCurrentValue(modName, val / 100, player);

	inline public function getTargetPercent(modName:String, player:Int)
		return !register.exists(getActualModName(modName)) ? 0 : get(modName).getTargetPercent(player);

	inline public function getTargetValue(modName:String, player:Int)
		return !register.exists(getActualModName(modName)) ? 0 : get(modName).getTargetValue(player);
    
	public function getCMod(data:Int, player:Int, ?defaultSpeed:Float){
		var daSpeed = getValue('cmod${data}', player);
		if (daSpeed < 0){
			daSpeed = getValue('cmod', player);

			if (daSpeed < 0){
				if (defaultSpeed == null)
					return state.songSpeed;
				else
					return defaultSpeed;
			}
		}

		return daSpeed;
	}

	public function getXMod(data:Int, player:Int)
		return getValue("xmod", player) * getValue('xmod${data}', player);
	
	inline public function getNoteSpeed(note:Note, pN:Int, ?songSpeed:Float)
		return getCMod(note.column, pN, songSpeed) * note.multSpeed * getXMod(note.column, pN);
	

	public function getActiveMods(pN:Int){
		if(activeMods[pN]==null){
            trace("generating active mods for player " + pN);
			activeMods[pN] = [];
			touchedMods[pN] = [];
            setDefaultValues(pN);
		}
		return activeMods[pN];
	}

	public function setCurrentValue(modName:String, val:Float, player:Int = -1)
	{
		if (player == -1)
		{
			for (pN => mods in activeMods)
				setCurrentValue(modName, val, pN);
		}
		else
		{
			var daMod = get(modName);
			if (daMod == null)
				return;
			daMod.setCurrentValue(val, player);
		}
	}

	public function touchMod(name:String, player:Int)
	{
        if(player < 0)return;

		if (touchedMods[player] == null)
			touchedMods[player] = [];

		if (!touchedMods[player].contains(name))
			touchedMods[player].push(name);
	}

    public function setValue(modName:String, val:Float, player:Int=-1){
		if (player == -1)
		{
			for (pN => mods in activeMods)
				setValue(modName, val, pN);
		}else{
            var daMod = get(modName);
			if (daMod == null)
				return;
            
			daMod.setValue(val, player);
        }
    }

    public function updateActiveMods(player:Int){
        if(player == -1){
            for(pN => mods in activeMods)
                updateActiveMods(pN);

            return;
        }

		var active_mods = getActiveMods(player);
        
        // remove currently inactive mods from the active mods
        var discarded_mods:Array<String> = [];
		var activated_mods:Array<String> = [];
        for(mod in modArray){
            var mod_name = mod.getName();
            if(active_mods.contains(mod_name)){
                if(!mod.shouldExecute(player, mod.getValue(player))){
                    var can_discard:Bool = true;
                    // before discarding we should be checking for submods and if THEY can execute
                    // if they can execute then we shouldnt be discarding this mod since the parent mod executes the logic for submods

                    for(submod_name => submod in mod.submods){
                        if (submod.shouldExecute(player, submod.getValue(player)))
                            can_discard = false; // we CANNOT discard since a submod can execute still
                    }


                    if(can_discard)
                        discarded_mods.push(mod_name); // shit is inactive, remove it later (cant in this loop)
                    
                }
            }else{

                if(mod.shouldExecute(player, mod.getValue(player))){
					if (mod.parent != null && !activated_mods.contains(mod.parent.getName()) && !active_mods.contains(mod.parent.getName()))
						activated_mods.push(mod.parent.getName());
					activated_mods.push(mod.getName());
                }
            }
        }

		// remove all inactive mods (we do it after pushing new ones so that we dont end up checking mods we KNOW arent executing)
		for (mod_name in discarded_mods){
			//trace("discarded " + mod_name + " for " + player);
			active_mods.remove(mod_name);
        }
		
		for (mod in activated_mods){
            if(!active_mods.contains(mod)){ // prob a redundant check but better safe than sorry
			    active_mods.push(mod);
				//trace("activated " + mod + " for " + player);
            }
        }
        
		active_mods.sort((a, b) -> Std.int(get(a).getOrder() - get(b).getOrder()));
    }

	function runNodes()
	{
		if (nodeArray.length > 0)
		{
			for (player => mods in touchedMods)
			{
				nodeIndex++; // used to prevent calling the same node over and over when it has multiple inputs
				// could do a ran_nodes array but honestly this is probably better for optimization since its not having to store the entire node, just an index

				for (mod in mods)
				{
					if (nodes.exists(mod))
					{
						var garbage = [];
						for (node in nodes.get(mod))
						{
							if (node.lastIndex != nodeIndex)
							{
								var input_values:Array<Float> = [];

								for (input_mod in node.in_mods)
									input_values.push(getValue(input_mod, player));

								var output_values:Array<Float> = node.nodeFunc(input_values, player);

								
								if (node.out_mods.length > 0)
								{ // if theres outputs
                                    if (output_values.length < node.out_mods.length)
                                    {
                                        for (i in node.out_mods.length...output_values.length)
                                            output_values.push(0); // TODO: check the out_mod to see if i should add in 0 or mod.getValue(player) depending on if its in in_mods
                                    }
                                    for (idx in 0...node.out_mods.length)
                                    {
                                        var output_value:Float = output_values[idx];
                                        var output_mod_name:String = node.out_mods[idx];
                                        var output_mod:Modifier = get(output_mod_name);
                                        if (output_mod == null){
                                            trace(output_mod_name + " is not a valid output, look into fixing pl0x");
                                            continue;
                                        }
                                        var current_value:Float = output_mod.getValue(player);
                                        // if the output is also an input then set it directly, otherwise add it
                                        if (node.in_mods.contains(output_mod_name))
                                            output_mod.setCurrentValue(output_value, player);
                                        else
                                            output_mod.setCurrentValue(current_value + output_value, player);
                                    }
								}
							}
						}
						for (node in garbage)
							nodes.get(mod).remove(node);
					}
				}
			}
		}
	}

	public function update(elapsed:Float, beat:Float, step:Float)
	{
		//tempActiveMods = [[], []];
		for (pN => mods in activeMods)
		{
			touchedMods[pN] = [];
			for (mod in mods)
				touchedMods[pN].push(mod);
		}

		timeline.updateMods(step);
        
        for (mod in modArray)
        {
            mod._internalUpdate();
            if (mod.doesUpdate())
				mod.update(elapsed, beat);
        }
		timeline.updateFuncs(step);
        runNodes();
        for(pN in 0...touchedMods.length)touchedMods[pN] = [];
		updateActiveMods(-1);
	}

 	public var playerAmount:Int = 2;
	public var playerOOBIsCentered:Bool = true; // Player Out of Bounds is centered
	public var vPadding:Float = 45;

	public function getBaseX(direction:Int, player:Float, receptorAmount:Int = 4):Float
	{
		if (playerOOBIsCentered && (player >= playerAmount || player < 0))
			player = 0.5; // replicating old behaviour for upcoming modcharts
		
		var spaceWidth = FlxG.width / playerAmount;
		var spaceX = spaceWidth * (playerAmount-1-player);

		var baseX:Float = spaceX + (spaceWidth - Note.swagWidth * receptorAmount) * 0.5;
		var x:Float = baseX + Note.swagWidth * direction;

		return x;
	}

	public function updateObject(beat:Float, obj:NoteObject, player:Int){
		if (obj.active)
		for (name in getActiveMods(player))
		{
			/*if (!obj.active)
				continue;*/

			var mod:Modifier = notemodRegister.get(name);
			if (mod==null) continue;
			
			if(obj.objType == NOTE){
				if (mod.ignoreUpdateNote()) continue;
				mod.updateNote(beat, cast obj, player);
			}
			else if(obj.objType == STRUM){
				if (mod.ignoreUpdateReceptor()) continue;
				mod.updateReceptor(beat, cast obj, player);
			}
		}
		
		if (obj.objType == NOTE){
			obj.updateHitbox();

			var cum:Note = cast obj;
			if(!cum.isSustainNote){
				obj.centerOrigin();
				obj.centerOffsets();
			}
			cum.offset.x += cum.typeOffsetX;
			cum.offset.y += cum.typeOffsetY;
		}else{
			obj.centerOrigin();
			obj.centerOffsets();
		}
    }

	public inline function getBaseVisPosD(diff:Float, songSpeed:Float = 1)
	{
		return (0.45 * (diff) * songSpeed);
	}

	public function getPos(diff:Float, tDiff:Float, beat:Float, data:Int, player:Int, obj:NoteObject, field:NoteField, ?exclusions:Array<String>, ?pos:Vector3):Vector3
	{
		if (!obj.alive) 
			return pos;

		if (exclusions == null) 
			exclusions = []; // since [] cant be a default value for.. some reason?? "its not constant!!" kys haxe
		
		if (pos == null)
			pos = new Vector3();
		
		pos.setTo(
			(Note.swagWidth * 0.5) + getBaseX(data, player, field.field.keyCount),
			(Note.swagWidth * 0.5) + 50 + diff,
			0
		);

 		for (name in getActiveMods(player)){
			/*if (!obj.alive) 
				continue;*/
			
			if (exclusions.contains(name)) 
				continue; // because some modifiers may want the path without reverse, for example. (which is actually more common than you'd think!)
			
			var mod:Modifier = notemodRegister.get(name);
			if (mod != null && !mod.ignorePos())
				pos = mod.getPos(diff, tDiff, beat, pos, data, player, obj, field);
        }

		return pos;
    }

	public function getFieldZoom(zoom:Float, beat:Float, songPos:Float, player:Int, field:NoteField, ?exclusions:Array<String>):Float
	{
		if (exclusions == null)
			exclusions = [];

		for (name in getActiveMods(player))
		{
			if (exclusions.contains(name)) 
				continue;

			var mod:Modifier = miscmodRegister.get(name);
			if (mod != null && mod.affectsField()) 
				zoom = mod.getFieldZoom(zoom, beat, songPos, player, field);
		}

		return zoom;
	}

	public function modifyVertex(beat:Float, vert:Vector3, idx:Int, obj:NoteObject, pos:Vector3, player:Int, data:Int, field:NoteField, ?exclusions:Array<String>):Vector3
	{
		if (!obj.active) 
			return vert;

		if (exclusions == null) 
			exclusions = [];

		for (name in getActiveMods(player))
		{
			/*if (!obj.active) 
				return vert;*/

			if (exclusions.contains(name))
				continue;

			var mod:Modifier = notemodRegister.get(name);
			if (mod != null && mod.isRenderMod())
				vert = mod.modifyVert(beat, vert, idx, obj, pos, player, data, field);
		}
		return vert;
	}

	public function getExtraInfo(diff:Float, tDiff:Float, beat:Float, ?info:RenderInfo, obj:NoteObject, player:Int, data:Int, ?exclusions:Array<String>):RenderInfo
	{
		if (!obj.active)
			return info;

		if (exclusions == null)
			exclusions = [];

		if (info == null){
			info = {
				alpha: 1,
				glow: 0,
				scale: FlxPoint.weak(0.7, 0.7)
			};
		}

		for (name in getActiveMods(player))
		{
			/*if (!obj.active)
				return info;*/

			if (exclusions.contains(name))
				continue;

			var mod:Modifier = notemodRegister.get(name);
			if (mod != null && mod.isRenderMod())
				info = mod.getExtraInfo(diff, tDiff, beat, info, obj, player, data);
		}

		return info;
	}

	public function queueEase(step:Float, endStep:Float, modName:String, target:Float, style:Any, player:Int = -1, ?startVal:Float)
	{
		/*
		if (startVal != null)
			queueSet(step, modName, startVal, player);
		*/

		//modName = getActualModName(modName);

		var easeFunc:EaseFunction = FlxEase.linear;


		if (style is String){
			// most common use of the style var is to just use an existing FlxEase
			easeFunc = CoolUtil.getEaseFromString(style);

		}else if (Reflect.isFunction(style)){
			// probably gonna be useful SOMEWHERE
			// maybe custom eases?
			easeFunc = style;
        }
        

		if (player == -1)
			for (pN => mods in activeMods)
				timeline.addEvent(new ModEaseEvent(step, endStep, modName, target, easeFunc, pN, this, startVal));				
		else
			timeline.addEvent(new ModEaseEvent(step, endStep, modName, target, easeFunc, player, this, startVal));
	}

	public function queueSet(step:Float, modName:String, target:Float, player:Int = -1)
	{
		//modName = getActualModName(modName);
		if (player == -1)
			for (pN => mods in activeMods)
				timeline.addEvent(new SetEvent(step, modName, target, pN, this));
		else
			timeline.addEvent(new SetEvent(step, modName, target, player, this));
		
	}

	public function queueEaseP(step:Float, endStep:Float, modName:String, percent:Float, style:Dynamic = 'linear', player:Int = -1, ?startVal:Float)
		queueEase(step, endStep, modName, percent * 0.01, style, player, startVal * 0.01);
	
	public function queueSetP(step:Float, modName:String, percent:Float, player:Int = -1)
		queueSet(step, modName, percent * 0.01, player);

	public function queueFunc(step:Float, endStep:Float, callback:(CallbackEvent, Float) -> Void)
		timeline.addEvent(new StepCallbackEvent(step, endStep, callback, this));
    
	public function queueFuncOnce(step:Float, callback:(CallbackEvent, Float) -> Void)
		timeline.addEvent(new CallbackEvent(step, callback, this));
	
	public function queueEaseFunc(step:Float, endStep:Float, func:EaseFunction, callback:(EaseEvent, Float, Float) -> Void)
		timeline.addEvent(new EaseEvent(step, endStep, func, callback, this));

}