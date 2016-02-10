package nodepointlc;

%EN =
(
	"Home", "Home",
	"Product", "Product",
	"Release", "Release",
	"Model", "Model",
	"Project", "Project",
	"Goal", "Goal",
	"Milestone", "Milestone",
	"Resource", "Resource",
	"Location", "Location",
	"Update", "Update",
	"Application", "Application",
	"Platform", "Platform",
	"Version", "Version",
	"Asset", "Asset",
	"Type", "Type",
	"Instance", "Instance",
	
);

%FR =
(
	"Home", "Accueil",
	"Product", "Produit",
	"Release", "Version",
	"Model", "Modèle",
	"Project", "Projet",
	"Goal", "Objectif",
	"Milestone", "Étape",
	"Resource", "Ressource",
	"Location", "Emplacement",
	"Update", "Mise à jour",
	"Application", "Application",
	"Platform", "Plate-forme",
	"Version", "Version",
	"Asset", "Atout",
	"Type", "Genre",
	"Instance", "Article",
	
);

sub lang()
{
	my ($m, $l) = @_;
	if($l eq "FR") { return %FR; }
	#if($l eq "BR") { return %BR; }
	return %EN;
}