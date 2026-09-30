extends SceneTree
var failures:=0
func check(v:bool,s:String)->void:
	if v:print("PASS: "+s)
	else:failures+=1;printerr("FAIL: "+s)
func _initialize()->void:call_deferred("run")
func run()->void:
	var folder:="user://round2-rewards-"+str(Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var p:=PlayerProfile.new(folder+"/p.json");var c:=CampaignService.new(p)
	for id in ["forest_treebridge","forest_spore_corridor","forest_moss_guardian","mine_entrance","mine_fracture"]:p.data.campaign.first_clears[id]=true
	p.save()
	var mine:=c.begin_run("mine_furnace");var mine_reward:=c.settle_run(mine.run_id,"win",{})
	var rock:=false
	for id in p.data.inventory.equipment:rock=rock or p.data.inventory.equipment[id].template_id=="rockcore"
	check(mine_reward.ok and rock and int(mine_reward.rewards.gold)==310,"mine boss groups include 180 first clear and rockcore")
	var q:=PlayerProfile.new(folder+"/q.json");var qc:=CampaignService.new(q);var run:=qc.begin_run("forest_treebridge")
	var first:=qc.settle_run(run.run_id,"win",{"medkits_used":0,"player_actions":6})
	check(first.rewards.groups.size()==4 and int(first.rewards.gold)==285,"first chapter target groups reward once")
	var repeat:=qc.begin_run("forest_treebridge");var second:=qc.settle_run(repeat.run_id,"win",{"medkits_used":0,"player_actions":6})
	check(second.rewards.groups.size()==1,"completed objectives do not repeat")
	print("REWARDS UI FAILURES: %d"%failures);quit(0 if failures==0 else 1)
