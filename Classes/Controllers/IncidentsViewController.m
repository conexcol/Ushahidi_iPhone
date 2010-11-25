/*****************************************************************************
 ** Copyright (c) 2010 Ushahidi Inc
 ** All rights reserved
 ** Contact: team@ushahidi.com
 ** Website: http://www.ushahidi.com
 **
 ** GNU Lesser General Public License Usage
 ** This file may be used under the terms of the GNU Lesser
 ** General Public License version 3 as published by the Free Software
 ** Foundation and appearing in the file LICENSE.LGPL included in the
 ** packaging of this file. Please review the following information to
 ** ensure the GNU Lesser General Public License version 3 requirements
 ** will be met: http://www.gnu.org/licenses/lgpl.html.
 **
 **
 ** If you have questions regarding the use of this file, please contact
 ** Ushahidi developers at team@ushahidi.com.
 **
 *****************************************************************************/

#import "IncidentsViewController.h"
#import "AddIncidentViewController.h"
#import "ViewIncidentViewController.h"
#import "MapViewController.h"
#import "IncidentTableCell.h"
#import "TableCellFactory.h"
#import "UIColor+Extension.h"
#import "LoadingViewController.h"
#import "NSDate+Extension.h"
#import "AlertView.h"
#import "InputView.h"
#import "Incident.h"
#import "Deployment.h"
#import "Category.h"
#import "MKMapView+Extension.h"
#import "MapAnnotation.h"
#import "Settings.h"
#import "TableHeaderView.h"
#import "IncidentTableView.h"
#import "IncidentMapView.h"

@interface IncidentsViewController ()

@property(nonatomic,retain) NSMutableArray *pending;
@property(nonatomic,retain) ItemPicker *itemPicker;
@property(nonatomic,retain) NSMutableArray *categories;
@property(nonatomic,retain) Category *category;

- (void) updateLastSyncLabel;
- (void) pushViewIncidentsViewController;
- (void) populateMapPins;

@end

@implementation IncidentsViewController

@synthesize addIncidentViewController, viewIncidentViewController, mapView, deployment, tableSort, mapType, pending;
@synthesize incidentTableView, incidentMapView, itemPicker, categories, category, filterButton;

typedef enum {
	ViewModeTable,
	ViewModeMap
} ViewMode;

typedef enum {
	TableSectionPending,
	TableSectionIncidents
} TableSection;

typedef enum {
	TableSortDate,
	TableSortTitle,
	TableSortVerified
} TableSort;

typedef enum {
	MapTypeRoad,
	MapTypeSatellite,
	MapTypeHybrid
} MapType;

#pragma mark -
#pragma mark Handlers

- (IBAction) add:(id)sender {
	DLog(@"");
	[self presentModalViewController:self.addIncidentViewController animated:YES];
}

- (IBAction) refresh:(id)sender {
	DLog(@"");
	self.incidentTableView.refreshButton.enabled = NO;
	self.incidentMapView.refreshButton.enabled = NO;
	[self.loadingView showWithMessage:NSLocalizedString(@"Loading...", @"Loading...")];
	[[Ushahidi sharedUshahidi] getIncidentsForDelegate:self];
	[[Ushahidi sharedUshahidi] uploadIncidentsForDelegate:self];
}

- (IBAction) tableSortChanged:(id)sender {
	UISegmentedControl *segmentControl = (UISegmentedControl *)sender;
	if (segmentControl.selectedSegmentIndex == TableSortDate) {
		DLog(@"TableSortDate");
	}
	else if (segmentControl.selectedSegmentIndex == TableSortTitle) {
		DLog(@"TableSortTitle");
	}
	else if (segmentControl.selectedSegmentIndex == TableSortVerified) {
		DLog(@"TableSortVerified");
	}
	[self filterRows:YES];
}

- (IBAction) mapTypeChanged:(id)sender {
	if (self.mapType.selectedSegmentIndex == MapTypeRoad) {
		DLog(@"MapTypeRoad");
		self.mapView.mapType = MKMapTypeStandard;
	}
	else if (self.mapType.selectedSegmentIndex == MapTypeSatellite) {
		DLog(@"MapTypeSatellite");
		self.mapView.mapType = MKMapTypeSatellite;
	}
	else if (self.mapType.selectedSegmentIndex == MapTypeHybrid) {
		DLog(@"MapTypeHybrid");
		self.mapView.mapType = MKMapTypeHybrid;
	}
}

- (IBAction) toggleReportsAndMap:(id)sender {
	DLog(@"");
	UISegmentedControl *segmentControl = (UISegmentedControl *)sender;
	if (segmentControl.selectedSegmentIndex == ViewModeTable) {
		DLog(@"ViewModeTable");
		self.incidentTableView.frame = self.view.frame;
		[UIView beginAnimations:nil context:nil];
		[UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationDuration:0.6];
		[UIView setAnimationTransition:UIViewAnimationTransitionFlipFromLeft forView:self.view cache:YES];
		[self.incidentMapView removeFromSuperview];
		[self.view addSubview:self.incidentTableView];
		[UIView commitAnimations];
		self.filterButton.enabled = [self.categories count] > 0;
	}
	else if (segmentControl.selectedSegmentIndex == ViewModeMap) {
		DLog(@"ViewModeMap");
		self.incidentMapView.frame = self.view.frame;
		[UIView beginAnimations:nil context:nil];
		[UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationDuration:0.6];
		[UIView setAnimationTransition:UIViewAnimationTransitionFlipFromRight forView:self.view cache:YES];
		[self.incidentTableView removeFromSuperview];
		[self.view addSubview:self.incidentMapView];
		[UIView commitAnimations];
		[self populateMapPins];
	}
}

- (IBAction) filterChanged:(id)sender event:(UIEvent*)event {
	NSMutableArray *items = [NSMutableArray arrayWithObject:NSLocalizedString(@" --- ALL CATEGORIES --- ", @" --- ALL CATEGORIES --- ")];
	for (Category *theCategory in self.categories) {
		[items addObject:theCategory.title];
	}
	if (event != nil) {
		UIView *toolbar = [[event.allTouches anyObject] view];
		DLog(@"toolbar: %@", toolbar);
		CGRect rect = CGRectMake(toolbar.frame.origin.x, self.view.frame.size.height - toolbar.frame.size.height, toolbar.frame.size.width, toolbar.frame.size.height);
		[self.itemPicker showWithItems:items withSelected:[self.category title] forRect:rect];
	}
	else {
		[self.itemPicker showWithItems:items withSelected:[self.category title] forRect:CGRectMake(100, self.view.frame.size.height, 0, 0)];	
	}
}

- (void) updateLastSyncLabel {
	if (self.deployment.lastSync) {
		[self setTableFooter:[NSString stringWithFormat:@"%@ %@", 
							  NSLocalizedString(@"Last Sync", @"Last Sync"), 
							  [self.deployment.lastSync dateToString:@"h:mm a, MMMM d, yyyy"]]];	
	}
	else {
		[self setTableFooter:nil];
	}
}

- (void) populateMapPins {
	[self.mapView removeAllPins];
	self.mapView.showsUserLocation = YES;
	for (Incident *incident in self.allRows) {
		[self.mapView addPinWithTitle:incident.title 
							 subtitle:incident.dateString 
							 latitude:incident.latitude 
							longitude:incident.longitude
							   object:incident
							 pinColor:MKPinAnnotationColorRed];
	}
	for (Incident *incident in self.pending) {
		[self.mapView addPinWithTitle:incident.title 
							 subtitle:incident.dateString 
							 latitude:incident.latitude 
							longitude:incident.longitude 
							   object:incident
							 pinColor:MKPinAnnotationColorPurple];
	}
	[self.mapView resizeRegionToFitAllPins:YES];
}

#pragma mark -
#pragma mark UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];
	self.pending = [[NSMutableArray alloc] initWithCapacity:0];
	self.itemPicker = [[ItemPicker alloc] initWithDelegate:self forController:self];
	self.tableView.backgroundColor = [UIColor ushahidiLiteTan];
	self.oddRowColor = [UIColor ushahidiLiteTan];
	self.evenRowColor = [UIColor ushahidiDarkTan];
	[self showSearchBarWithPlaceholder:NSLocalizedString(@"Search reports...", @"Search reports...")];
	[self setHeader:NSLocalizedString(@"Pending Upload", @"Pending Upload") atSection:TableSectionPending];
	[self setHeader:NSLocalizedString(@"All Categories", @"All Categories") atSection:TableSectionIncidents];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	DLog(@"willBePushed: %d", self.willBePushed);
	if (self.incidentTableView.superview == nil && self.incidentMapView.superview == nil) {
		self.incidentTableView.frame = self.view.frame;
		self.incidentMapView.frame = self.view.frame;
		[self.view addSubview:self.incidentTableView];
	}
	if (self.deployment != nil) {
		self.title = self.deployment.name;
	}
	[self.allRows removeAllObjects];
	if (self.willBePushed) {
		[self.allRows addObjectsFromArray:[[Ushahidi sharedUshahidi] getIncidentsForDelegate:self]];
		self.category = nil;
		self.categories = [NSMutableArray arrayWithArray:[[Ushahidi sharedUshahidi] getCategoriesForDelegate:self]];
		[self setHeader:NSLocalizedString(@"All Categories", @"All Categories") atSection:TableSectionIncidents];
	}
	else {
		[self.allRows addObjectsFromArray:[[Ushahidi sharedUshahidi] getIncidents]];
	}
	[self.pending removeAllObjects];
	[self.pending addObjectsFromArray:[[Ushahidi sharedUshahidi] getIncidentsPending]];
	[self filterRows:NO];
	if (self.incidentTableView.superview != nil) {
		[self updateLastSyncLabel];
		[self.tableView reloadData];
		self.filterButton.enabled = [self.categories count] > 0;
	}
	else if (self.incidentMapView.superview != nil) {
		[self populateMapPins];
	}
}

- (void)dealloc {
	[addIncidentViewController release];
	[viewIncidentViewController release];
	[mapView release];
	[deployment release];
	[tableSort release];
	[mapType release];
	[pending release];
	[itemPicker release];
	[categories release];
	[category release];
	[filterButton release];
    [super dealloc];
}

#pragma mark -
#pragma mark UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)theTableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)theTableView numberOfRowsInSection:(NSInteger)section {
	if (section == TableSectionPending) {
		return [self.pending count];
	}
	if (section == TableSectionIncidents) {
		return [self.filteredRows count];
	}
	return 0;
}

- (CGFloat)tableView:(UITableView *)theTableView heightForHeaderInSection:(NSInteger)section {
	if (section == TableSectionPending && [self.pending count] > 0) {
		return [TableHeaderView getViewHeight];
	}
	else if (section == TableSectionIncidents) {
		return [TableHeaderView getViewHeight];
	}
	return 0;
}

- (CGFloat)tableView:(UITableView *)theTableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return [IncidentTableCell getCellHeight];
}

- (UITableViewCell *)tableView:(UITableView *)theTableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	IncidentTableCell *cell = [TableCellFactory getIncidentTableCellForTable:theTableView indexPath:indexPath];
	Incident *incident = indexPath.section == TableSectionIncidents
		? [self filteredRowAtIndexPath:indexPath] : [self.pending objectAtIndex:indexPath.row];
	if (incident != nil) {
		[cell setTitle:incident.title];
		[cell setLocation:incident.location];
		[cell setCategory:incident.categoryNames];
		[cell setDate:incident.dateString];
		[cell setVerified:incident.verified];
		UIImage *image = [incident getFirstPhotoThumbnail];
		if (image != nil) {
			[cell setImage:image];
		}
		else if (incident.map != nil) {
			[cell setImage:incident.map];
		}
		else {
			[cell setImage:nil];
		}
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.selectionStyle = UITableViewCellSelectionStyleGray;
		[cell setUploading:indexPath.section == TableSectionPending && incident.uploading];
	}
	else {
		[cell setTitle:nil];
		[cell setLocation:nil];
		[cell setCategory:nil];
		[cell setDate:nil];
		[cell setImage:nil];
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	return cell;
}

- (void)tableView:(UITableView *)theTableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[theTableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == TableSectionIncidents) {
		self.viewIncidentViewController.pending = NO;
		self.viewIncidentViewController.incident = [self filteredRowAtIndexPath:indexPath];
		self.viewIncidentViewController.incidents = self.filteredRows;
	}
	else {
		self.viewIncidentViewController.pending = YES;
		self.viewIncidentViewController.incident = [self.pending objectAtIndex:indexPath.row];
		self.viewIncidentViewController.incidents = self.pending;
	}
	if (self.editing) {
		[self.view endEditing:YES];
		[self performSelector:@selector(pushViewIncidentsViewController) withObject:nil afterDelay:0.1];
	}
	else {
		[self pushViewIncidentsViewController];
	}
}

- (void) pushViewIncidentsViewController {
	[self.navigationController pushViewController:self.viewIncidentViewController animated:YES];
}

#pragma mark -
#pragma mark UISearchBarDelegate

- (void) filterRows:(BOOL)reloadTable {
	[self.filteredRows removeAllObjects];
	NSString *searchText = [self getSearchText];
	NSArray *incidents;
	if (self.tableSort.selectedSegmentIndex == TableSortDate) {
		incidents = [self.allRows sortedArrayUsingSelector:@selector(compareByDate:)];
	}
	else if (self.tableSort.selectedSegmentIndex == TableSortVerified) {
		incidents = [self.allRows sortedArrayUsingSelector:@selector(compareByVerified:)];
	}
	else {
		incidents = [self.allRows sortedArrayUsingSelector:@selector(compareByTitle:)];
	}
	for (Incident *incident in incidents) {
		if (self.category != nil) {
			if ([incident hasCategory:self.category] && [incident matchesString:searchText]) {
				[self.filteredRows addObject:incident];
			}
		}
		else if ([incident matchesString:searchText]) {
			[self.filteredRows addObject:incident];
		}
	}
	if (reloadTable) {
		[self.tableView reloadData];	
		[self.tableView flashScrollIndicators];
	}
} 

#pragma mark -
#pragma mark MKMapViewDelegate

- (void)mapViewWillStartLoadingMap:(MKMapView *)theMapView {
	DLog(@"");
}

- (void)mapViewDidFinishLoadingMap:(MKMapView *)theMapView {
	DLog(@"");
}

- (void)mapViewDidFailLoadingMap:(MKMapView *)theMapView withError:(NSError *)error {
	DLog(@"error: %@", [error localizedDescription]);
}

#pragma mark -
#pragma mark UshahidiDelegate

- (void) downloadedFromUshahidi:(Ushahidi *)ushahidi incidents:(NSArray *)incidents pending:(NSArray *)thePending error:(NSError *)error hasChanges:(BOOL)hasChanges {
	if (error != nil) {
		DLog(@"error: %@", [error localizedDescription]);
		if ([self.loadingView isShowing]) {
			[self.alertView showWithTitle:NSLocalizedString(@"Error", @"Error") andMessage:[error localizedDescription]];
		}
	}
	else if(hasChanges) {
		DLog(@"incidents: %d", [incidents count]);
		[self updateLastSyncLabel];
		[self.loadingView hide];
		[self.allRows removeAllObjects];
		if (self.tableSort.selectedSegmentIndex == TableSortDate) {
			[self.allRows addObjectsFromArray:[incidents sortedArrayUsingSelector:@selector(compareByDate:)]];
		}
		else if (self.tableSort.selectedSegmentIndex == TableSortVerified) {
			[self.allRows addObjectsFromArray:[incidents sortedArrayUsingSelector:@selector(compareByVerified:)]];
		}
		else {
			[self.allRows addObjectsFromArray:[incidents sortedArrayUsingSelector:@selector(compareByTitle:)]];
		}
		[self.filteredRows removeAllObjects];
		[self.filteredRows addObjectsFromArray:self.allRows];
		[self.pending removeAllObjects];
		[self.pending addObjectsFromArray:thePending];
		if (self.incidentTableView.superview != nil) {
			[self.tableView reloadData];
			[self.tableView flashScrollIndicators];	
		}
		else if (self.incidentMapView.superview != nil) {
			[self populateMapPins];
		}
		DLog(@"Re-Adding Incidents");
	}
	else {
		DLog(@"No Changes Incidents");
		[self updateLastSyncLabel];
		[self.tableView reloadData];
	}
	[self.loadingView hide];
	self.incidentTableView.refreshButton.enabled = YES;
	self.incidentMapView.refreshButton.enabled = YES;
}

- (void) uploadingToUshahidi:(Ushahidi *)ushahidi incident:(Incident *)incident {
	if (incident != nil){
		DLog(@"Incident: %@", incident.title);
		NSInteger row = [self.pending indexOfObject:incident];
		if (row > -1) {
			NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:TableSectionPending];
			IncidentTableCell *cell = (IncidentTableCell *)[self.tableView cellForRowAtIndexPath:indexPath];
			if (cell != nil) {
				[cell setUploading:YES];
			}
		}
	}
	else {
		DLog(@"Incident is NULL");
	}
}

- (void) uploadedToUshahidi:(Ushahidi *)ushahidi incident:(Incident *)incident error:(NSError *)error {
	if (incident != nil){
		DLog(@"Incident: %@", incident.title);
		NSInteger row = [self.pending indexOfObject:incident];
		if (row > -1) {
			NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:TableSectionPending];
			IncidentTableCell *cell = (IncidentTableCell *)[self.tableView cellForRowAtIndexPath:indexPath];
			if (cell != nil) {
				[cell setUploading:NO];
			}
		}
	}
	else {
		DLog(@"Incident is NULL");
	}
}

- (void) downloadedFromUshahidi:(Ushahidi *)ushahidi incident:(Incident *)incident map:(UIImage *)map {
	DLog(@"downloadedFromUshahidi:incident:map:");
	NSInteger row = [self.filteredRows indexOfObject:incident];
	if (row != NSNotFound) {
		NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:TableSectionIncidents];
		IncidentTableCell *cell = (IncidentTableCell *)[self.tableView cellForRowAtIndexPath:indexPath];
		if (cell != nil && [incident getFirstPhotoThumbnail] == nil) {
			[cell setImage:map];
		}
	}
	else {
		[self.tableView reloadData];
	}
}

- (void) downloadedFromUshahidi:(Ushahidi *)ushahidi incident:(Incident *)incident photo:(Photo *)photo {
	DLog(@"downloadedFromUshahidi:incident:photo:%@ indexPath:%@", [photo url], [photo indexPath]);
	if (photo != nil && photo.indexPath != nil) {
		IncidentTableCell *cell = (IncidentTableCell *)[self.tableView cellForRowAtIndexPath:photo.indexPath];
		if (cell != nil) {
			if (photo.thumbnail != nil) {
				[cell setImage:photo.thumbnail];
			}
			else {
				[cell setImage:photo.image];
			}
		}	
	}
	else {
		[self.tableView reloadData];
	}
}

- (void) downloadedFromUshahidi:(Ushahidi *)ushahidi categories:(NSArray *)theCategories error:(NSError *)error hasChanges:(BOOL)hasChanges {
	if (error != nil) {
		DLog(@"error: %@", [error localizedDescription]);
	}
	else if(hasChanges) {
		[self.categories removeAllObjects];
		for (Category *theCategory in theCategories) {
			[self.categories addObject:theCategory];
		}
		DLog(@"Re-Adding Categories");
	}
	else {
		DLog(@"No Changes Categories");
	}
	self.filterButton.enabled = [self.categories count] > 0;
}

#pragma mark -
#pragma mark MKMapView

- (MKAnnotationView *) mapView:(MKMapView *)theMapView viewForAnnotation:(id <MKAnnotation>)annotation {
	MKPinAnnotationView *annotationView = (MKPinAnnotationView *)[theMapView dequeueReusableAnnotationViewWithIdentifier:@"MKPinAnnotationView"];
	if (annotationView == nil) {
		 annotationView = [[[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"MKPinAnnotationView"] autorelease];
	}
	annotationView.animatesDrop = NO;
	annotationView.canShowCallout = YES;
	if ([annotation class] == MKUserLocation.class) {
		annotationView.pinColor = MKPinAnnotationColorGreen;
	}
	else {
		DLog(@"annotation: %@", [annotation class]);
		if ([annotation isKindOfClass:[MapAnnotation class]]) {
			MapAnnotation *mapAnnotation = (MapAnnotation *)annotation;
			annotationView.pinColor = mapAnnotation.pinColor;
		}
		else {
			annotationView.pinColor = MKPinAnnotationColorRed;
		}
		UIButton *annotationButton = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
		[annotationButton addTarget:self action:@selector(annotationClicked:) forControlEvents:UIControlEventTouchUpInside];
		annotationView.rightCalloutAccessoryView = annotationButton;
	}
	return annotationView;
}

- (void) annotationClicked:(UIButton *)button {
	MKPinAnnotationView *annotationView = (MKPinAnnotationView *)[[button superview] superview];
	MapAnnotation *mapAnnotation = (MapAnnotation *)annotationView.annotation;
	DLog(@"title:%@ latitude:%f longitude:%f", mapAnnotation.title, mapAnnotation.coordinate.latitude, mapAnnotation.coordinate.longitude);
	self.viewIncidentViewController.incident = (Incident *)mapAnnotation.object;
	if (mapAnnotation.pinColor == MKPinAnnotationColorRed) {
		self.viewIncidentViewController.incidents = self.allRows;	
	}
	else {
		self.viewIncidentViewController.incidents = self.pending;
	}
	[self.navigationController pushViewController:self.viewIncidentViewController animated:YES];	
}

#pragma mark -
#pragma mark ItemPickerDelegate
		 
- (void) itemPickerReturned:(ItemPicker *)itemPicker item:(NSString *)item {
	DLog(@"itemPickerReturned: %@", item);
	self.category = nil;
	for (Category *theCategory in self.categories) {
		if ([theCategory.title isEqualToString:item]) {
			self.category = theCategory;
			DLog(@"Category: %@", theCategory.title);
			break;
		}
	}
	if (self.category != nil) {
		[self setHeader:self.category.title atSection:TableSectionIncidents];
	}
	else {
		[self setHeader:NSLocalizedString(@"All Categories", @"All Categories") atSection:TableSectionIncidents];
	}
	[self filterRows:YES];
}

- (void) itemPickerCancelled:(ItemPicker *)itemPicker {
	DLog(@"itemPickerCancelled");
}

@end
